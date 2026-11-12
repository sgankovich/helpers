#!/usr/bin/env bash
# AWS Emulator helpers (Docker). Source this file; do not execute it:
#   source /path/to/emulator.sh
# Then run: emu-help
#
# Requirements: docker, curl, aws CLI v2 and (optionally) terraform.
# Nothing personal is stored here: the Dockerfile is embedded in emu-build and
# all paths are derived from $HOME or the current directory.

EMU_PORT="${EMU_PORT:-9297}"
EMU_DIR="$HOME/.aws/emulator/$EMU_PORT"

# Build the image. Dockerfile is embedded (passed via stdin), always uses the latest package.
# Usage: emu-build [extra docker build args, e.g. --pull --no-cache]
emu-build() {
  docker build -t aws-emulator "$@" - <<'DOCKERFILE'
FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal
ARG TARGETARCH
RUN case "$TARGETARCH" in arm64) a=aarch64 ;; amd64) a=x86_64 ;; *) exit 1 ;; esac \
    && curl -fsSLo /tmp/aws-emulator.rpm \
       "https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/latest/aws-emulator-$a.rpm" \
    && rpm -i /tmp/aws-emulator.rpm && rm /tmp/aws-emulator.rpm \
    && mkdir -p /home/emulator && chown 1000 /home/emulator
USER 1000
ENV HOME=/home/emulator
ENV PATH=/opt/aws-emulator/bin:$PATH
EXPOSE 9297
ENTRYPOINT ["aws-emulator", "-b", "0.0.0.0"]
DOCKERFILE
}

# Start the container (builds the image first if missing) and wait until it is healthy.
emu-start() {
  mkdir -p "$EMU_DIR"
  docker info >/dev/null 2>&1 || { echo "Docker is not running"; return 1; }
  docker image inspect aws-emulator >/dev/null 2>&1 || emu-build || return 1
  docker network create aws-emulator >/dev/null 2>&1
  docker run -d --rm --name aws-emulator --network aws-emulator \
    --cap-drop ALL --security-opt no-new-privileges --read-only \
    -e EMULATOR_TELEMETRY=off \
    -p 127.0.0.1:"$EMU_PORT":"$EMU_PORT" \
    -v "$EMU_DIR:/home/emulator/.aws/emulator/$EMU_PORT" \
    aws-emulator -p "$EMU_PORT" "$@" >/dev/null || return 1
  local _
  for _ in $(seq 30); do
    curl -sf --cacert "$EMU_DIR/ca.pem" "https://127.0.0.1:$EMU_PORT/__admin/health" >/dev/null \
      && { echo "emulator up"; return 0; }
    sleep 1
  done
  echo "emulator did not become healthy"
  return 1
}

emu-stop() { docker stop aws-emulator; }

# Point THIS shell at the emulator (run after emu-start). Prints the account id: must be 000000000000.
emu-env() {
  [ -f "$EMU_DIR/emulator_credentials" ] || { echo "emu-env: emulator is not running (run emu-start)" >&2; return 1; }
  export AWS_ENDPOINT_URL="https://127.0.0.1:$EMU_PORT"
  export AWS_SHARED_CREDENTIALS_FILE="$EMU_DIR/emulator_credentials"
  export AWS_CONFIG_FILE="$EMU_DIR/config"
  export AWS_CA_BUNDLE="$EMU_DIR/ca.pem"
  export AWS_EC2_METADATA_DISABLED=true
  export AWS_REGION=us-east-1
  export AWS_DEFAULT_REGION=us-east-1
  export AWS_PAGER=""
  export AWS_S3_USE_PATH_STYLE=true
  # Real credentials would win over the credentials file and be sent to the emulator.
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE \
    AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN AWS_ROLE_SESSION_NAME \
    AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_CONTAINER_CREDENTIALS_FULL_URI AWS_CONTAINER_AUTHORIZATION_TOKEN
  local acc
  acc=$(aws sts get-caller-identity --query Account --output text) || return 1
  echo "$acc"
  if [ "$acc" != "000000000000" ]; then
    echo "WARNING: not the emulator account - requests may go to real AWS. Run emu-off." >&2
    return 1
  fi
}

# Disconnect this shell from the emulator.
emu-off() {
  unset AWS_ENDPOINT_URL AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE AWS_EC2_METADATA_DISABLED \
    AWS_REGION AWS_DEFAULT_REGION AWS_CA_BUNDLE AWS_PAGER AWS_S3_USE_PATH_STYLE
}

# Run terraform against the emulator in the CURRENT directory (isolated subshell).
emu-tf() {
  if ! ls ./*.tf >/dev/null 2>&1; then
    echo "emu-tf: no *.tf files in the current directory ($PWD)." >&2
    echo "cd into a directory with Terraform code and try again." >&2
    return 1
  fi
  ( emu-env >/dev/null && terraform "$@" )
}

# Remove local terraform state in the CURRENT directory (use after emu-stop / restart).
emu-tf-clear() {
  if ! ls ./*.tf >/dev/null 2>&1; then
    echo "emu-tf-clear: no *.tf files in the current directory ($PWD)." >&2
    return 1
  fi
  rm -f terraform.tfstate terraform.tfstate.backup && echo "tf state cleared"
}

emu-status() {
  local st
  st=$(docker ps --filter name=^aws-emulator$ --format '{{.Status}}' 2>/dev/null)
  if [ -n "$st" ]; then
    echo "container: $st"
    echo "health:    $(curl -sf --cacert "$EMU_DIR/ca.pem" "https://127.0.0.1:$EMU_PORT/__admin/health" || echo unreachable)"
  else
    echo "container: stopped"
  fi
  if [ -n "$AWS_ENDPOINT_URL" ]; then
    echo "this shell: connected to $AWS_ENDPOINT_URL"
  else
    echo "this shell: NOT connected (real AWS defaults)"
  fi
}

emu-help() {
  cat <<'HELP'
AWS Emulator - instructions (local AWS emulator in Docker, port 9297)

COMMANDS
  emu-build       Build the image (Dockerfile is embedded). Use --pull --no-cache to update.
  emu-start       Start the container (builds the image first if missing) and wait until healthy.
  emu-status      Show container state, health, and whether this shell is connected.
  emu-env         Connect the CURRENT shell to the emulator (aws, terraform, SDKs).
                  Prints the account id: must be 000000000000.
  emu-off         Disconnect this shell from the emulator (back to normal AWS).
  emu-tf <args>   Run `terraform <args>` in the CURRENT directory (must contain *.tf)
                  against the emulator; otherwise prints an error. The shell stays clean.
  emu-tf-clear    Remove terraform.tfstate* in the CURRENT directory.
  emu-stop        Stop the emulator. ALL data is lost (it lives in memory only).
  emu-help        This help.

TYPICAL FLOW
  emu-start
  cd <directory with *.tf>
  emu-tf init
  emu-tf plan
  emu-tf apply -auto-approve
  emu-env && aws s3 ls
  emu-tf destroy -auto-approve    # optional
  emu-off
  emu-stop
  emu-tf-clear                    # required before the next start

IMPORTANT
  * Without emu-env (or emu-tf) aws commands go to REAL AWS. Always check:
    `aws sts get-caller-identity` must show account 000000000000.
    If it shows another account, stop immediately, run emu-off, then emu-env.
  * After emu-stop the emulator state is empty, so run emu-tf-clear, otherwise
    terraform will think the resources still exist.
  * The emulator listens on 127.0.0.1 only. Never publish the port on all interfaces.
  * Do not use production data and do not disable TLS verification.
  * One Region (us-east-1) and one account per emulator.
  * IAM policies, bucket policies and KMS key policies cannot be tested on the emulator.
  * Another port: set EMU_PORT=9300 before sourcing (the port is passed to the emulator automatically).

TROUBLESHOOTING
  "Docker is not running"        Start Docker Desktop.
  Port 9297 is busy              Check: lsof -i :9297 ; or run emu-stop.
  TLS / certificate error        The certificate is new on every start: run emu-env again.
  BucketAlreadyExists            Bucket left from a previous run: emu-stop, emu-start, emu-tf-clear.
  s3control / 000000000000.127.0.0.1 error
                                 Use AWS provider ~> 5.100 (6.x does not work with the emulator).
  EC2 / SSM / CloudFormation     Coverage is partial: DescribeTags and some operations return 501 NotImplemented.
HELP
}
