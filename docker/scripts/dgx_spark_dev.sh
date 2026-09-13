#!/usr/bin/env bash
set -Eeuo pipefail

# Isolated Apollo ARM64 development harness for DGX Spark.
# It intentionally does not source dev_start.sh: that script manages shared
# Apollo containers, ~/.apollo, and map/audio volumes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
STATE_DIR="${APOLLO_DGX_SPARK_STATE_DIR:-${REPO_ROOT}/.dgx-spark}"
CONTAINER="${APOLLO_DGX_SPARK_CONTAINER:-apollo_dgx_spark_${USER}}"
DEFAULT_IMAGE="apolloauto/apollo:dev-aarch64-20.04-20240626_1642"
MIRROR_IMAGE="registry.baidubce.com/${DEFAULT_IMAGE}"
IMAGE="${APOLLO_DGX_SPARK_IMAGE:-${DEFAULT_IMAGE}}"
GPU_MODE="${APOLLO_DGX_SPARK_GPU:-auto}"
GPU_ID="${APOLLO_DGX_SPARK_GPU_ID:-0}"
SHM_SIZE="${APOLLO_DGX_SPARK_SHM_SIZE:-2G}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

usage() {
  cat <<EOF
Usage: $0 [--name NAME] [--image IMAGE] [--cpu] {start|shell|stop|status}

Environment overrides:
  APOLLO_DGX_SPARK_CONTAINER  Container name (default: ${CONTAINER})
  APOLLO_DGX_SPARK_IMAGE      Existing ARM64 dev image (default: ${DEFAULT_IMAGE})
  APOLLO_DGX_SPARK_STATE_DIR  Isolated state directory (default: ${STATE_DIR})
  APOLLO_DGX_SPARK_GPU        auto|cdi|runtime|none (default: ${GPU_MODE})
  APOLLO_DGX_SPARK_GPU_ID     NVIDIA GPU/CDI device ID (default: ${GPU_ID})

This harness never pulls images, removes containers, or touches Apollo map/audio
volumes. It uses a private network namespace and "stop" stops only the
configured container.
EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

check_host() {
  require_cmd docker
  [[ "$(uname -s)" == Linux ]] || die "Linux host required"
  [[ "$(uname -m)" == aarch64 ]] || die "aarch64 host required (got $(uname -m))"
  docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"
  if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    if [[ "${IMAGE}" == "${DEFAULT_IMAGE}" ]] &&
      docker image inspect "${MIRROR_IMAGE}" >/dev/null 2>&1; then
      IMAGE="${MIRROR_IMAGE}"
    else
      die "image is not available locally: ${IMAGE}; refusing to pull"
    fi
  fi
}

container_exists() {
  docker container inspect "${CONTAINER}" >/dev/null 2>&1
}

container_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null || true)" == true ]]
}

select_gpu_args() {
  GPU_ARGS=()
  GPU_VISIBLE_DEVICES=none
  case "${GPU_MODE}" in
    none|cpu) return 0 ;;
    cdi)
      [[ -e /var/run/cdi/nvidia.yaml ]] ||
        die "NVIDIA CDI spec not found; use --cpu or APOLLO_DGX_SPARK_GPU=runtime"
      GPU_ARGS+=(--device="nvidia.com/gpu=${GPU_ID}")
      GPU_VISIBLE_DEVICES="${GPU_ID}"
      ;;
    runtime)
      docker info --format '{{json .Runtimes}}' | grep -q '"nvidia"' ||
        die "Docker nvidia runtime is unavailable; use --cpu"
      GPU_ARGS+=(--runtime=nvidia)
      GPU_VISIBLE_DEVICES="${GPU_ID}"
      ;;
    auto)
      if [[ -e /var/run/cdi/nvidia.yaml ]]; then
        GPU_ARGS+=(--device="nvidia.com/gpu=${GPU_ID}")
        GPU_VISIBLE_DEVICES="${GPU_ID}"
      elif docker info --format '{{json .Runtimes}}' | grep -q '"nvidia"'; then
        GPU_ARGS+=(--runtime=nvidia)
        GPU_VISIBLE_DEVICES="${GPU_ID}"
      else
        die "no NVIDIA CDI/runtime found; use --cpu"
      fi
      ;;
    *) die "invalid GPU mode: ${GPU_MODE} (expected auto|cdi|runtime|none)" ;;
  esac
}

start_container() {
  check_host
  mkdir -p "${STATE_DIR}"/{config,home,cache,data}
  select_gpu_args

  if container_exists; then
    if container_running; then
      info "already running: ${CONTAINER}"
    else
      docker start "${CONTAINER}" >/dev/null
      info "started existing container: ${CONTAINER}"
    fi
    return 0
  fi

  docker run -d \
    --name "${CONTAINER}" \
    --label "apollo.dgx-spark.harness=true" \
    --label "apollo.dgx-spark.repo=${REPO_ROOT}" \
    --hostname apollo-dgx-spark \
    --shm-size "${SHM_SIZE}" \
    --workdir /apollo \
    --env HOME=/apollo/.dgx-spark/home \
    --env USER="${USER}" \
    --env APOLLO_DGX_SPARK_UID="$(id -u)" \
    --env APOLLO_IN_DOCKER=true \
    --env APOLLO_CONFIG_HOME=/apollo/.dgx-spark/config \
    --env APOLLO_CACHE_DIR=/apollo/.cache \
    --env APOLLO_BAZEL_DIST_DIR=/apollo/.cache/distdir \
    --env NVIDIA_VISIBLE_DEVICES="${GPU_VISIBLE_DEVICES}" \
    --env NVIDIA_DRIVER_CAPABILITIES=compute,video,graphics,utility \
    --volume "${REPO_ROOT}:/apollo" \
    --volume "${STATE_DIR}/config:/apollo/.dgx-spark/config" \
    --volume "${STATE_DIR}/home:/apollo/.dgx-spark/home" \
    --volume "${STATE_DIR}/cache:/apollo/.cache" \
    --volume "${STATE_DIR}/data:/apollo/data" \
    --volume /etc/localtime:/etc/localtime:ro \
    "${GPU_ARGS[@]}" \
    "${IMAGE}" /bin/bash -lc '
      set -eu
      user_name="$(getent passwd "${APOLLO_DGX_SPARK_UID}" | cut -d: -f1)"
      test -n "${user_name}"
      printf "%s ALL=(ALL) NOPASSWD:ALL\\n" "${user_name}" >/etc/sudoers.d/apollo-dgx-spark
      chmod 440 /etc/sudoers.d/apollo-dgx-spark
      exec sleep infinity
    '
  info "started: ${CONTAINER}"
}

shell_container() {
  container_running || die "container is not running: ${CONTAINER}; run start first"
  docker exec -it -u "$(id -u):$(id -g)" \
    -e HOME=/apollo/.dgx-spark/home \
    -e HISTFILE=/apollo/.dgx-spark/bash_history \
    -e HTTP_PROXY= -e HTTPS_PROXY= -e ALL_PROXY= \
    -e http_proxy= -e https_proxy= -e all_proxy= -e NO_PROXY='*' -e no_proxy='*' \
    "${CONTAINER}" /bin/bash
}

status_container() {
  if ! container_exists; then
    info "absent: ${CONTAINER}"
    return 0
  fi
  docker inspect --format \
    'name={{.Name}} status={{.State.Status}} image={{.Config.Image}} mounts={{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' \
    "${CONTAINER}"
}

parse_args() {
  ACTION=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) [[ $# -ge 2 ]] || die "--name requires a value"; CONTAINER="$2"; shift 2 ;;
      --image) [[ $# -ge 2 ]] || die "--image requires a value"; IMAGE="$2"; shift 2 ;;
      --gpu-id) [[ $# -ge 2 ]] || die "--gpu-id requires a value"; GPU_ID="$2"; shift 2 ;;
      --cpu) GPU_MODE=none; shift ;;
      -h|--help) usage; exit 0 ;;
      start|shell|stop|status)
        [[ -z "${ACTION}" ]] || die "only one action may be specified"
        ACTION="$1"; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  [[ -n "${ACTION}" ]] || { usage >&2; exit 2; }
}

parse_args "$@"
case "${ACTION}" in
  start) start_container ;;
  shell) shell_container ;;
  status) status_container ;;
  stop)
    container_exists && docker stop "${CONTAINER}" >/dev/null && info "stopped: ${CONTAINER}" ||
      info "absent or already stopped: ${CONTAINER}"
    ;;
esac
