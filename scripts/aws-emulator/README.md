# aws-emulator

Shell helpers to run [AWS Emulator](https://github.com/aws/aws-emulator) in Docker (the only way on macOS/Windows)
and point the AWS CLI / Terraform at it. Nothing personal is stored: the Dockerfile is embedded in `emu-build`
and all paths come from `$HOME` or the current directory.

## Prerequisites

`docker` (running), `curl`, AWS CLI v2, optionally `terraform`.

## Setup on a new machine

```bash
git clone https://github.com/sgankovich/helpers.git ~/repositories/helpers
echo 'source ~/repositories/helpers/scripts/aws-emulator/emulator.sh' >> ~/.bashrc
source ~/.bashrc
emu-help
```

## Commands

| Command | Description |
|---------|-------------|
| `emu-build [args]` | Build the image (Dockerfile embedded). Use `--pull --no-cache` to update. |
| `emu-start` | Start the container (builds the image if missing) and wait for health. |
| `emu-status` | Container state, health, and whether this shell is connected. |
| `emu-env` | Connect the current shell to the emulator; prints the account (must be `000000000000`). |
| `emu-off` | Disconnect the shell. |
| `emu-tf <args>` | Run `terraform <args>` against the emulator in the current directory (requires `*.tf`). |
| `emu-tf-clear` | Remove `terraform.tfstate*` in the current directory. |
| `emu-stop` | Stop the emulator (all state is lost, it lives in memory only). |
| `emu-help` | Detailed instructions. |

## Typical flow

```bash
emu-start
cd path/to/terraform
emu-tf init && emu-tf apply -auto-approve
emu-env && aws s3 ls
emu-off; emu-stop; emu-tf-clear
```

## Notes

- Without `emu-env`/`emu-tf` the AWS CLI talks to **real AWS**. Check `aws sts get-caller-identity` shows `000000000000`.
- Terraform AWS provider 6.x does not work with the emulator for S3 buckets (S3 Control uses `<account>.host`
  not covered by the emulator certificate); use `~> 5.100`.
- Coverage is partial per service (e.g. EC2 `DescribeTags` is not implemented).
- The emulator listens on `127.0.0.1` only. Custom port: `EMU_PORT=9300` before sourcing.
- Telemetry is turned off in `emu-start`.
