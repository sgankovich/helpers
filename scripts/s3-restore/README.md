# S3 Restore

Bulk restore and status checking tools for S3 objects archived in Glacier, Deep Archive, or Intelligent-Tiering storage classes.

## Contents

- **[restore.py](#restorepy)** — Initiate bulk restore of archived S3 objects
- **[check.py](#checkpy)** — Monitor restore status of previously initiated restore operations

## Usage

### 1. Initiate Restore

```bash
# Dry run - preview objects without initiating restore
python scripts/restore.py --dry-run

# Real restore - initiate restore operations
python scripts/restore.py
```

### 2. Check Restore Status

```bash
# Check status of restore operations
python scripts/check.py
```

## Configuration

Both scripts share the same configuration section at the top of each file. Update these variables before running:

```python
BUCKET = 'your-s3-bucket-name'      # S3 bucket name (without s3://)
PREFIXES = [
    'path/to/folder1/',              # Add one entry per folder to restore
    'path/to/folder2/',              # Use '' to scan the entire bucket
]
TIER    = 'Standard'                 # Standard (~12 h) | Expedited (~5 min, higher cost)
DAYS    = 1                          # Days to keep the restored copy accessible
WORKERS = 20                         # Parallel threads for processing
```

**Important:** Keep the `BUCKET` and `PREFIXES` values in sync between `restore.py` and `check.py`.

## Prerequisites

- Python 3.6+
- `boto3` library: `pip install boto3`
- AWS credentials configured via:
  - Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
  - `~/.aws/credentials` file
  - IAM role (for EC2, ECS, Lambda, etc.)

## Supported Storage Classes

| Storage Class | Restore Method | Approx. Time | Notes |
|--------------|---------------|--------------|-------|
| GLACIER | GlacierJobParameters | ~12 hours | Standard tier |
| DEEP_ARCHIVE | GlacierJobParameters | ~12 hours | Standard tier |
| INTELLIGENT_TIERING (Archive Access) | No GlacierJobParameters | ~12 hours | Automatic detection |
| INTELLIGENT_TIERING (Deep Archive Access) | No GlacierJobParameters | ~12 hours | Automatic detection |
| INTELLIGENT_TIERING (Frequent/Infrequent) | N/A | N/A | Already accessible, skipped |

## How It Works

### restore.py

1. Lists all objects in the specified bucket and prefixes
2. Displays summary: object count, total size, estimated cost
3. In dry-run mode: shows first 30 objects and exits
4. In real mode: waits 5 seconds for cancellation, then initiates parallel restore operations
5. Handles different storage classes automatically:
   - Attempts GLACIER/DEEP_ARCHIVE restore first (with GlacierJobParameters)
   - Falls back to INTELLIGENT_TIERING restore (without GlacierJobParameters) if first attempt fails
   - Skips objects that are already accessible
6. Reports statistics: initiated, already in progress, skipped, errors

### check.py

1. Lists all objects in the same bucket and prefixes as restore.py
2. Concurrently checks each object's restore status via `head_object` API
3. Categorizes objects into four statuses:
   - **available**: Restored copy is ready or object is directly accessible
   - **restoring**: Restore job is in progress
   - **archived**: Object is archived but restore has not been initiated
   - **error**: Failed to check (permissions, network, etc.)
4. Displays progress during checking and final statistics

## Typical Workflow

```bash
# Step 1: Preview what will be restored
python scripts/restore.py --dry-run

# Step 2: Initiate restore (after verifying the preview)
python scripts/restore.py

# Step 3: Wait ~12 hours for Standard tier, or ~5 minutes for Expedited

# Step 4: Check status
python scripts/check.py

# Step 5: Repeat check.py every few hours until all files show as "available"
```

## Cost Estimation

- Standard tier restore: ~$0.02 per GB restored
- Expedited tier restore: ~$0.03 per GB restored
- Additional data retrieval fees may apply based on your AWS pricing

The script displays an estimated cost before initiating restore operations.

## Output Examples

### restore.py output:
```
📂 Listing objects...
   path/to/folder1/ → 1500 objects
   path/to/folder2/ → 3500 objects

============================================================
📊 SUMMARY
   Objects:  5,000
   Size:     2.50 TB (2560.0 GB)
   Tier:     Standard  (~12 h for Standard, ~5 min for Expedited)
   Est cost: ~$51.20  (Standard tier restore fee)
============================================================

🚀 Starting restore (20 threads)...
   Press Ctrl+C within 5 s to cancel
  [  100/5000]  ✓ 100  ⏳ 0  ⏭ 0  ✗ 0  | 20/s | ~4.2 min remaining
...
```

### check.py output:
```
📂 Listing objects...
   Total: 5,000 objects

🔍 Checking restore status...
   checked 1000/5000...

============================================================
📊 RESTORE STATUS

   ✅ Available (restored):      5000  (100.0%)
   ⏳ Restoring (in progress):      0  (0.0%)
   🧊 Archived (not started):      0  (0.0%)
   ❌ Check errors:                0
============================================================
🎉 ALL FILES AVAILABLE — ready to use.
```
