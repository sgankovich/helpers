"""
check.py — Check restore status of S3 objects archived in Glacier / Intelligent-Tiering.

Run this after restore.py to monitor progress.

Usage:
  python check.py

Prerequisites:
  pip install boto3
  AWS credentials configured via env vars, ~/.aws/credentials, or IAM role.
"""

import boto3
from concurrent.futures import ThreadPoolExecutor
from botocore.config import Config

# ============================================================
# CONFIGURATION — update these values before running
# ============================================================
BUCKET = 'your-s3-bucket-name'   # S3 bucket name (without s3://)
PREFIXES = [
    'path/to/folder1/',           # Add one entry per folder to restore
    'path/to/folder2/',           # Use '' to scan the entire bucket
]
WORKERS = 20                      # Parallel threads; increase for large datasets
# ============================================================

config = Config(
    max_pool_connections=50,
    retries={'max_attempts': 5, 'mode': 'adaptive'}
)
s3 = boto3.client('s3', config=config)

# --- 1. Collect object keys ---
print("📂 Listing objects...")
all_keys  = []
paginator = s3.get_paginator('list_objects_v2')

for prefix in PREFIXES:
    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix):
        for obj in page.get('Contents', []):
            all_keys.append(obj['Key'])

print(f"   Total: {len(all_keys):,} objects\n")

# --- 2. Check restore status for each object ---
print("🔍 Checking restore status...\n")

stats   = {'available': 0, 'restoring': 0, 'archived': 0, 'error': 0}
samples = {}   # up to 3 example keys per status, useful for diagnostics


def check(key):
    """
    Return the restore status for a single object:

      available  — restored copy is ready, or object is not archived (directly accessible)
      restoring  — restore job is in progress (ongoing-request="true")
      archived   — object is archived but restore has not been initiated
      error      — head_object call failed (permissions, network, etc.)
    """
    try:
        head    = s3.head_object(Bucket=BUCKET, Key=key)
        archive = head.get('ArchiveStatus', '')
        restore = head.get('Restore', '')

        if not archive:
            # No ArchiveStatus → object is in a standard/accessible tier
            return 'available'
        elif 'ongoing-request="true"' in restore:
            return 'restoring'
        else:
            return 'archived'
    except Exception:
        return 'error'


completed = 0
with ThreadPoolExecutor(max_workers=WORKERS) as executor:
    futures = {executor.submit(check, k): k for k in all_keys}

    for future in futures:
        key    = futures[future]
        result = future.result()
        stats[result] += 1
        completed += 1

        # Keep a few example keys per status for diagnostics
        if len(samples.get(result, [])) < 3:
            samples.setdefault(result, []).append(key)

        if completed % 1000 == 0:
            print(f"   checked {completed}/{len(all_keys)}...")

total         = len(all_keys)
pct_available = stats['available'] / total * 100 if total else 0
pct_restoring = stats['restoring'] / total * 100 if total else 0
pct_archived  = stats['archived']  / total * 100 if total else 0

print(f"\n{'=' * 60}")
print(f"""
📊 RESTORE STATUS

   ✅ Available (restored):   {stats['available']:>6}  ({pct_available:.1f}%)
   ⏳ Restoring (in progress):{stats['restoring']:>5}  ({pct_restoring:.1f}%)
   🧊 Archived (not started): {stats['archived']:>5}  ({pct_archived:.1f}%)
   ❌ Check errors:           {stats['error']:>6}
""")

if stats['available'] == total:
    print("🎉 ALL FILES AVAILABLE — ready to use.")
elif stats['restoring'] > 0:
    print("⏳ Restore in progress — re-run check.py in a few hours.")
elif stats['archived'] > 0:
    print("⚠️  Some files were not submitted for restore — run restore.py again.")

print(f"{'=' * 60}")
