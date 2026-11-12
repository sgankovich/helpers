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
    echo "emu-tf: у бягучым каталогу ($PWD) няма *.tf файлаў." >&2
    echo "Перайдзіце ў каталог з terraform-кодам і паўтарыце." >&2
    return 1
  fi
  ( emu-env >/dev/null && terraform "$@" )
}

# Remove local terraform state in the CURRENT directory (use after emu-stop / restart).
emu-tf-clear() {
  if ! ls ./*.tf >/dev/null 2>&1; then
    echo "emu-tf-clear: у бягучым каталогу ($PWD) няма *.tf файлаў." >&2
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
AWS Emulator — інструкцыя (лакальны эмулятар AWS у Docker, порт 9297)

КАМАНДЫ
  emu-build       Збірае вобраз (Dockerfile убудаваны). Аргументы: --pull --no-cache для абнаўлення.
  emu-start       Запускае кантэйнер (калі няма вобраза — спачатку збірае яго сам) і чакае гатоўнасці.
  emu-status      Паказвае стан кантэйнера, health-check і ці падлучаны гэты тэрмінал.
  emu-env         Падключае ЦЯПЕРАШНІ тэрмінал да эмулятара (aws, terraform, SDK).
                  Друкуе нумар акаўнта: павінен быць 000000000000.
  emu-off         Адключае тэрмінал ад эмулятара (вяртае звычайны AWS).
  emu-tf <args>   Запускае `terraform <args>` у БЯГУЧЫМ каталогу (дзе ёсць *.tf)
                  супраць эмулятара; інакш паказвае памылку. Тэрмінал застаецца чыстым.
  emu-tf-clear    Выдаляе terraform.tfstate* у БЯГУЧЫМ каталогу.
  emu-stop        Спыняе эмулятар. УСЕ даныя губляюцца (захоўваюцца толькі ў памяці).
  emu-help        Гэтая даведка.

ТЫПАВЫ ПРАЦЭС
  emu-start
  cd <каталог з *.tf>
  emu-tf init
  emu-tf plan
  emu-tf apply -auto-approve
  emu-env && aws s3 ls
  emu-tf destroy -auto-approve    # па жаданні
  emu-off
  emu-stop
  emu-tf-clear                    # абавязкова перад наступным запускам

ВАЖНА
  * Без emu-env (або emu-tf) каманды aws ідуць у РЭАЛЬНЫ AWS. Заўсёды правярайце:
    `aws sts get-caller-identity` павінен паказаць акаўнт 000000000000.
    Калі іншы — неадкладна спыніцеся і запусціце emu-off, потым emu-env.
  * Пасля emu-stop стан эмулятара пусты, таму ВЫДАЛІЦЕ state праз emu-tf-clear,
    інакш terraform будзе думаць, што рэсурсы яшчэ існуюць.
  * Эмулятар слухае толькі 127.0.0.1. Не публікуйце порт на ўсіх інтэрфейсах.
  * Не выкарыстоўвайце прадакшн-даныя і не адключайце праверку TLS.
  * Адзін рэгіён (us-east-1) і адзін акаўнт на адзін эмулятар.
  * Праверка IAM-палітык, bucket policy і KMS key policy на эмулятары не працуе.
  * Іншы порт: EMU_PORT=9300 перад source (порт перадаецца эмулятару аўтаматычна).

ЧАСТЫЯ ПРАБЛЕМЫ
  "Docker is not running"        Запусціце Docker Desktop.
  Порт 9297 заняты               Праверце: lsof -i :9297 ; або emu-stop.
  TLS / certificate error        Сертыфікат новы пры кожным старце: зрабіце emu-env нанова.
  BucketAlreadyExists            Бакет застаўся ад ранейшага запуску: emu-stop, emu-start, emu-tf-clear.
  Памылка s3control / 000000000000.127.0.0.1
                                 Выкарыстоўвайце AWS-правайдар ~> 5.100 (у 6.x ён не працуе з эмулятарам).
  EC2 / SSM / CloudFormation     Пакрыццё частковае: DescribeTags і некаторыя аперацыі вяртаюць 501 NotImplemented.
HELP
}
