"""
restore.py — Bulk restore of S3 objects from Glacier / Deep Archive / Intelligent-Tiering.

Supports:
  - GLACIER and DEEP_ARCHIVE storage classes  (uses GlacierJobParameters)
  - INTELLIGENT_TIERING Archive / Deep Archive Access tiers

Usage:
  python restore.py             # initiate restore
  python restore.py --dry-run  # preview only, no changes

Prerequisites:
  pip install boto3
  AWS credentials configured via env vars, ~/.aws/credentials, or IAM role.
"""

import boto3
import time
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from botocore.config import Config

# ============================================================
# CONFIGURATION — update these values before running
# ============================================================
BUCKET = 'your-s3-bucket-name'   # S3 bucket name (without s3://)
PREFIXES = [
    'path/to/folder1/',           # Add one entry per folder to restore
    'path/to/folder2/',           # Use '' to scan the entire bucket
]
TIER    = 'Standard'              # Standard (~12 h) | Expedited (~5 min, higher cost)
DAYS    = 1                       # Days to keep the restored copy accessible
WORKERS = 20                      # Parallel threads; increase for large datasets
# ============================================================

parser = argparse.ArgumentParser(description='Restore S3 objects from archive storage classes')
parser.add_argument('--dry-run', action='store_true',
                    help='Preview objects without initiating restore')
args = parser.parse_args()

config = Config(
    max_pool_connections=50,
    retries={'max_attempts': 5, 'mode': 'adaptive'}
)
s3 = boto3.client('s3', config=config)

# --- 1. Collect object keys ---
print("📂 Listing objects...")
all_keys   = []
total_size = 0
paginator  = s3.get_paginator('list_objects_v2')

for prefix in PREFIXES:
    prefix_count = 0
    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix):
        for obj in page.get('Contents', []):
            all_keys.append(obj['Key'])
            total_size   += obj.get('Size', 0)
            prefix_count += 1
    short = ('...' + prefix[-55:]) if len(prefix) > 55 else prefix
    print(f"   {short} → {prefix_count} objects")

total_gb  = total_size / (1024 ** 3)
total_tb  = total_size / (1024 ** 4)
cost_est  = total_gb * 0.02   # ~$0.02/GB for Standard tier restore

print(f"\n{'=' * 60}")
print(f"📊 SUMMARY")
print(f"   Objects:  {len(all_keys):,}")
print(f"   Size:     {total_tb:.2f} TB ({total_gb:.1f} GB)")
print(f"   Tier:     {TIER}  (~12 h for Standard, ~5 min for Expedited)")
print(f"   Est cost: ~${cost_est:.2f}  (Standard tier restore fee)")
print(f"{'=' * 60}")

# --- 2. Dry run — preview only, no API calls to restore_object ---
if args.dry_run:
    print(f"\n🔍 DRY RUN — first 30 objects:\n")
    for i, key in enumerate(all_keys[:30]):
        print(f"   {i+1:>4}. ...{key[-80:]}")
    if len(all_keys) > 30:
        print(f"\n   ... and {len(all_keys) - 30} more objects")
    print(f"\n✅ To run the real restore: python restore.py")
    exit(0)

# --- 3. Real restore ---
print(f"\n🚀 Starting restore ({WORKERS} threads)...")
print(f"   Press Ctrl+C within 5 s to cancel")
time.sleep(5)

stats  = {'initiated': 0, 'already': 0, 'skipped': 0, 'error': 0}
errors = []


def restore(key):
    """
    Restore a single object. Handles three storage class variants:

    1. GLACIER / DEEP_ARCHIVE
       → requires GlacierJobParameters; Standard tier takes ~12 h.

    2. INTELLIGENT_TIERING (Archive Access / Deep Archive Access tier)
       → RestoreRequest must be empty {}; Days and GlacierJobParameters are not accepted.

    3. INTELLIGENT_TIERING (Frequent / Infrequent Access tier)
       → object is already accessible; restore_object returns InvalidObjectState.
         Treated as 'skipped' (no restore needed).
    """
    try:
        # Attempt 1: GLACIER / DEEP_ARCHIVE path
        s3.restore_object(
            Bucket=BUCKET,
            Key=key,
            RestoreRequest={
                'Days': DAYS,
                'GlacierJobParameters': {'Tier': TIER},
            }
        )
        return 'initiated'
    except Exception as e:
        code = getattr(e, 'response', {}).get('Error', {}).get('Code', '')

        if code == 'RestoreAlreadyInProgress':
            return 'already'

        elif code == 'InvalidObjectState':
            # Object is in a non-archivable storage class (e.g. STANDARD) — nothing to do
            return 'skipped'

        elif code == 'InvalidArgument':
            # GlacierJobParameters not supported → object is in INTELLIGENT_TIERING.
            # For Archive Access / Deep Archive Access tiers the RestoreRequest must be
            # an empty dict {} — passing 'Days' also causes InvalidArgument.
            try:
                s3.restore_object(
                    Bucket=BUCKET,
                    Key=key,
                    RestoreRequest={}
                )
                return 'initiated'
            except Exception as e2:
                code2 = getattr(e2, 'response', {}).get('Error', {}).get('Code', '')
                if code2 == 'RestoreAlreadyInProgress':
                    return 'already'
                elif code2 == 'InvalidObjectState':
                    # Object is in INTELLIGENT_TIERING Frequent/Infrequent tier — already accessible
                    return 'skipped'
                else:
                    errors.append(f"{key}: {code2 or str(e2)}")
                    return 'error'

        else:
            errors.append(f"{key}: {code or str(e)}")
            return 'error'


start     = time.time()
completed = 0

with ThreadPoolExecutor(max_workers=WORKERS) as executor:
    futures = {executor.submit(restore, k): k for k in all_keys}

    for future in as_completed(futures):
        result = future.result()
        stats[result] += 1
        completed += 1

        if completed % 500 == 0:
            elapsed = time.time() - start
            rate    = completed / elapsed
            eta     = (len(all_keys) - completed) / rate / 60
            print(f"  [{completed:>6}/{len(all_keys)}]  "
                  f"✓ {stats['initiated']}  ⏳ {stats['already']}  "
                  f"⏭ {stats['skipped']}  ✗ {stats['error']}  "
                  f"| {rate:.0f}/s | ~{eta:.1f} min remaining")

elapsed = time.time() - start

print("=" * 60)
print(f"""
🏁 DONE in {elapsed / 60:.1f} min

   ✓ Restore initiated:    {stats['initiated']}
   ⏳ Already in progress: {stats['already']}
   ⏭ Not archived (ok):   {stats['skipped']}
   ✗ Errors:              {stats['error']}

┌──────────────────────────────────────────────┐
│  ⏰ Files will be available in ~12 h          │
│  💰 Est. cost: ~${cost_est:<6.2f}                      │
│  Run check.py to monitor restore progress    │
└──────────────────────────────────────────────┘
""")

if errors:
    print("❌ Errors (first 20):")
    for e in errors[:20]:
        print(f"   {e}")
