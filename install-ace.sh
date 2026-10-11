#!/usr/bin/env bash
# Interactive ACE-Step installer for Ubuntu x86-64 / NVIDIA.
# Run as the account that should own ACE-Step (root is supported).
set -Eeuo pipefail
exec > >(awk '{print " " $0; fflush()}') 2> >(awk '{print " " $0; fflush()}' >&2)
printf '\n\n'
trap 'printf "\n\n"' EXIT
trap 'printf "\nInstallation stopped at line %s. Fix the reported error and rerun.\n" "$LINENO" >&2' ERR

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ask() {
    local answer
    [[ -r /dev/tty ]] || die 'An interactive terminal is required.'
    printf '\n %s [y/N]: ' "$*" >/dev/tty
    read -r answer </dev/tty || return 1
    [[ "$answer" == y || "$answer" == Y || "$answer" == yes || "$answer" == YES ]]
}

INSTALL_DIR=${ACESTEP_INSTALL_DIR:-"$HOME/apps/ACE-Step-1.5"}
GPU_INDEX=${ACESTEP_GPU_INDEX:-0}
MIN_FREE_GIB=30
[[ "$INSTALL_DIR" == /* ]] || die 'ACESTEP_INSTALL_DIR must be an absolute path.'
[[ "$GPU_INDEX" =~ ^[0-9]+$ ]] || die 'ACESTEP_GPU_INDEX must be a numeric GPU index.'
[[ $# == 0 ]] || die 'No arguments supported. Set ACESTEP_INSTALL_DIR or ACESTEP_GPU_INDEX if needed.'
[[ -f /etc/os-release ]] || die 'Cannot identify the operating system.'
# shellcheck disable=SC1091
source /etc/os-release
[[ "$ID" == ubuntu ]] || die 'This installer supports Ubuntu only.'
[[ "$(uname -m)" == x86_64 ]] || die 'This installer supports x86-64 only.'
printf 'Ubuntu %s; install location: %s; GPU index: %s\n' "$VERSION_ID" "$INSTALL_DIR" "$GPU_INDEX"
resume=false
if [[ -e "$INSTALL_DIR" ]]; then
    command -v git >/dev/null || die 'Existing directory found, but git is unavailable to verify it.'
    [[ -d "$INSTALL_DIR/.git" ]] || die 'Existing directory is not an ACE-Step checkout. Choose a new install path.'
    origin=$(git -C "$INSTALL_DIR" remote get-url origin)
    [[ "${origin,,}" == https://github.com/ace-step/ace-step-1.5.git ]] || die 'Existing directory has an unexpected Git origin. It will not be modified.'
    complete=true
    for item in pyproject.toml start-ace.sh .venv/bin/python checkpoints/acestep-v15-turbo/config.json checkpoints/acestep-v15-turbo/model.safetensors checkpoints/vae/diffusion_pytorch_model.safetensors checkpoints/Qwen3-Embedding-0.6B/model.safetensors; do
        if [[ ! -s "$INSTALL_DIR/$item" ]]; then
            printf 'Missing or empty: %s\n' "$item"
            complete=false
        fi
    done
    if [[ "$complete" == true ]]; then
        if ! ACE_SPOT_ROOT="$INSTALL_DIR" "$INSTALL_DIR/.venv/bin/python" - <<'CHECK'
import importlib.util
for module in ('torch','gradio','transformers','soundfile'):
    assert importlib.util.find_spec(module) is not None, f'Missing package: {module}'
import json, struct
from pathlib import Path
root=Path(__import__('os').environ['ACE_SPOT_ROOT'])
# Model file spot-check: JSON headers and referenced tensor extents.
# This catches truncated weights without loading gigabytes into memory.
for relative in ('acestep-v15-turbo/model.safetensors', 'vae/diffusion_pytorch_model.safetensors', 'Qwen3-Embedding-0.6B/model.safetensors'):
    path=root/'checkpoints'/relative
    with path.open('rb') as f:
        header_size=struct.unpack('<Q', f.read(8))[0]
        assert 0<header_size<=100_000_000, f'Invalid weight header: {path}'
        header=json.loads(f.read(header_size))
    end=max((entry['data_offsets'][1] for name,entry in header.items() if name!='__metadata__'), default=0)
    assert path.stat().st_size >= 8+header_size+end, f'Truncated weights: {path}'
CHECK
        then complete=false; fi
    fi
    if [[ "$complete" == true ]]; then
        printf '\nExisting installation passed file/package spot checks.\n'
        if ! ask 'Reinstall/repair dependencies, model files, and launcher?'; then
            if ask 'Start the existing ACE installation now?'; then
                if bash "$INSTALL_DIR/start-ace.sh"; then
                    printf '\nACE session ended.\n'
                else
                    printf '\nACE did not start or its session ended with an error. The existing installation was not changed.\n' >&2
                fi
            fi
            exit 0
        fi
    else
        printf '\nThe existing installation is incomplete.\n'
        ask 'Repair the existing installation?' || die 'Repair declined; no installation changes made.'
    fi
    command -v flock >/dev/null || die 'flock is required to repair an existing installation.'
    exec 8>"$INSTALL_DIR/.ace-session.lock"
    flock -n 8 || die 'ACE is running. Stop it before repairing.'
    resume=true
fi

# Check resources before installing anything.
probe=$(dirname "$INSTALL_DIR")
while [[ ! -d "$probe" ]]; do probe=$(dirname "$probe"); done
free_kib=$(df -Pk "$probe" | awk 'END {print $4}')
(( free_kib >= MIN_FREE_GIB * 1024 * 1024 )) || die "At least ${MIN_FREE_GIB} GiB free disk space is required (installer policy)."

command -v nvidia-smi >/dev/null || die 'NVIDIA driver/nvidia-smi is missing. Install Ubuntu’s recommended proprietary NVIDIA driver, reboot, then rerun. The installer does not change GPU drivers.'
gpu_info=$(nvidia-smi -i "$GPU_INDEX" --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader,nounits) || die 'NVIDIA GPU/driver check failed.'
printf 'GPU: %s\n' "$gpu_info"
IFS=',' read -r gpu_name driver total_mem free_mem <<<"$gpu_info"
driver=${driver//[[:space:]]/}
total_mem=${total_mem//[[:space:]]/}
free_mem=${free_mem//[[:space:]]/}
[[ "$total_mem" =~ ^[0-9]+$ && "$free_mem" =~ ^[0-9]+$ ]] || die 'Could not read GPU memory.'
(( total_mem >= 8192 && free_mem >= 8192 )) || die 'At least 8 GiB total and currently free VRAM is required for this configuration. Unload Ollama/vLLM models and rerun.'
# Conservative policy: full CUDA 12.8 driver support, rather than relying
# on minor-version compatibility with older drivers.
dpkg --compare-versions "$driver" ge 570.26 || die "Driver $driver is older than this installer’s CUDA 12.8 baseline (570.26). Update the NVIDIA driver and reboot before rerunning."

admin=()
if (( EUID != 0 )); then admin=(sudo); fi
missing=()
for package in git curl ca-certificates ffmpeg libsndfile1 build-essential util-linux; do
    status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
    [[ "$status" == 'install ok installed' ]] || missing+=("$package")
done
if (( ${#missing[@]} )); then
    if (( EUID != 0 )); then command -v sudo >/dev/null || die 'sudo is required to install missing packages.'; fi
    printf 'Missing system prerequisites: %s\n' "${missing[*]}"
    ask 'Install these packages with apt?' || die 'Prerequisite installation declined. ACE-Step was not installed.'
    "${admin[@]}" apt-get update || die 'apt update failed. Resolve repository errors (including Caddy/Cloudsmith) before continuing.'
    "${admin[@]}" apt-get install -y "${missing[@]}"
fi
for package in git curl ca-certificates ffmpeg libsndfile1 build-essential util-linux; do
    [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" == 'install ok installed' ]] || die "Prerequisite remains missing: $package"
done
for tool in git curl ffmpeg flock; do command -v "$tool" >/dev/null || die "Required command missing: $tool"; done

for url in https://github.com/ace-step/ACE-Step-1.5 https://huggingface.co https://download.pytorch.org/whl/cu128/; do
    curl --fail --silent --show-error --location --max-time 45 --output /dev/null "$url" || die "Cannot access required download host: $url"
done

if ! command -v uv >/dev/null; then
    if [[ -x "$HOME/.local/bin/uv" ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    else
        ask 'Install uv in your user account? (downloads the official installer)' || die 'uv installation declined. ACE-Step was not installed.'
        temp_installer=$(mktemp)
        curl --fail --show-error --location --max-time 60 https://astral.sh/uv/install.sh -o "$temp_installer"
        sh "$temp_installer"
        rm -f "$temp_installer"
        export PATH="$HOME/.local/bin:$PATH"
    fi
fi
command -v uv >/dev/null || die 'uv is unavailable after installation.'
uv --version
if ! uv python find --managed-python 3.11 >/dev/null 2>&1; then
    ask 'Download an isolated Python 3.11 runtime with uv?' || die 'Python prerequisite declined. ACE-Step was not installed.'
    uv python install 3.11
fi
uv python find --managed-python 3.11 >/dev/null || die 'Python 3.11 prerequisite is not available.'

printf '\nAll initial prerequisite checks passed.\n'
ask "Install ACE-Step and download its dependencies/models into $INSTALL_DIR?" || die 'Installation declined.'
mkdir -p "$(dirname "$INSTALL_DIR")"
if [[ "$resume" == false ]]; then
    git clone https://github.com/ace-step/ACE-Step-1.5.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
git rev-parse HEAD > INSTALLED_COMMIT.txt
if [[ "$resume" == true ]]; then
    uv sync --python 3.11 --managed-python --reinstall
else
    uv sync --python 3.11 --managed-python
fi

# Validate actual CUDA execution, not just device discovery. This happens
# before downloading model weights or generating a launcher.
CUDA_VISIBLE_DEVICES="$GPU_INDEX" uv run python - <<'PY'
import ctypes
import torch
ctypes.CDLL('libsndfile.so.1')
assert torch.cuda.is_available(), 'PyTorch cannot use CUDA; check the driver.'
cap = torch.cuda.get_device_capability(0)
assert cap >= (7, 5), f'This installer targets Turing or newer, detected {cap}.'
dtype = torch.float32 if cap[0] < 8 else torch.bfloat16
x = torch.ones((64, 64), device='cuda', dtype=dtype)
y = x @ x
torch.cuda.synchronize()
assert torch.isfinite(y).all().item(), 'CUDA precision computation failed.'
print('GPU runtime verified:', torch.cuda.get_device_name(0), 'capability:', cap)
print('PyTorch:', torch.__version__, 'CUDA runtime:', torch.version.cuda)
print('Recommended ACE precision:', dtype)
PY

# Turbo and its shared components are bundled in the default main download.
uv run acestep-download

if [[ -f start-ace.sh ]]; then
    cp -p start-ace.sh "start-ace.sh.backup.$(date +%Y%m%d-%H%M%S)"
fi
cat > start-ace.sh <<'LAUNCHER'
#!/usr/bin/env bash
# ACE-Step launcher; Ubuntu/Linux, Bash. No environment activation required.
set -Eeuo pipefail
# Indent both streams; preserve progress output while flushing each line.
exec > >(awk '{print " " $0; fflush()}') 2> >(awk '{print " " $0; fflush()}' >&2)
printf '\n\n'
child=''
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ -n "$child" ]]; then kill -TERM -- "-$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi
    if [[ "${owns_lock:-false}" == true ]]; then rm -f -- "$session"; fi
    printf '\n\n'
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "\nError at line %s; startup stopped.\n" "$LINENO" >&2' ERR
fail() { printf '\n%s\n' "$*" >&2; exit 1; }
usage() {
cat <<'HELP'
Usage: start-ace [--local|--lan] [--auth|--no-auth] [--fp32|--fp16|--auto]
                 [--model NAME] [--port NUMBER] [--gpu INDEX]

Default: ask for LAN access [no], then browser login [yes].
Automatic precision; Turbo model; background startup.
--foreground keeps ACE attached to this terminal.
--status reports the managed server; --stop requests shutdown; --kill forces it.
--logs prints the last 80 log lines.
--auth enables browser protection; --no-auth starts without a login.
--username NAME and --password-file FILE supply credentials without prompts.
--non-interactive requires explicit --local/--lan and --auth/--no-auth.
For protected non-interactive startup, also supply --password-file.
Auto uses FP32 on Turing for ACE numerical stability, BF16 on Ampere+.
--fp16 forces FP16 even on cards where ACE may overflow.
--local binds localhost for SSH tunneling. LAN uses HTTP.

Models supported (must already be downloaded):
  acestep-v15-turbo, acestep-v15-sft, acestep-v15-base
  acestep-v15-xl-turbo, acestep-v15-xl-sft, acestep-v15-xl-base
Use 8 generation steps for Turbo; about 50 for SFT/base in the UI.

Environment defaults: ACESTEP_GPU_INDEX, ACESTEP_PORT, ACESTEP_DTYPE,
ACESTEP_MODEL. --help prints this message.
HELP
}
export ACESTEP_DTYPE="${ACESTEP_DTYPE:-auto}"
export ACESTEP_MODEL="${ACESTEP_MODEL:-acestep-v15-turbo}"
export ACESTEP_PORT="${ACESTEP_PORT:-7860}"
gpu="${ACESTEP_GPU_INDEX:-0}"
bind=127.0.0.1
access_mode=ask
auth_mode=ask
non_interactive=false
login_user_arg=
password_file=
foreground=false
action=start
while (( $# )); do
  case "$1" in
    --foreground) foreground=true; shift ;;
    --background) foreground=false; shift ;;
    --status|--stop|--kill|--logs) action="${1#--}"; shift ;;
    --help|-h) usage; exit 0 ;;
    --auth) auth_mode=yes; shift ;;
    --no-auth) auth_mode=no; shift ;;
    --non-interactive) non_interactive=true; shift ;;
    --local) bind=127.0.0.1; access_mode=local; shift ;;
    --lan) bind=0.0.0.0; access_mode=lan; shift ;;
    --fp32) export ACESTEP_DTYPE=float32; shift ;;
    --fp16) export ACESTEP_DTYPE=float16; shift ;;
    --auto) export ACESTEP_DTYPE=auto; shift ;;
    --model|--port|--gpu|--username|--password-file)
      (( $# >= 2 )) || fail "Missing value for $1"
      case "$1" in
        --model) export ACESTEP_MODEL="$2" ;;
        --port) export ACESTEP_PORT="$2" ;;
        --gpu) gpu="$2" ;;
        --username) login_user_arg="$2" ;;
        --password-file) password_file="$2" ;;
      esac
      shift 2 ;;
    *) fail "Unknown option: $1. Use --help." ;;
  esac
done
if [[ "$action" != start ]]; then
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
    if [[ "$action" == logs ]]; then
        [[ -f ace-server.log ]] || fail 'No background server log exists yet.'
        tail -n 80 ace-server.log
        exit 0
    fi
    [[ -x .venv/bin/python ]] || fail 'ACE Python environment is missing.'
    .venv/bin/python - "$action" <<'MANAGE'
import json, os, signal, sys, time
from pathlib import Path
p=Path('.ace-server.json')
def identity(pid):
    try:
        text=Path(f'/proc/{pid}/stat').read_text()
        fields=text.rsplit(')',1)[1].split()
        return fields[19], fields[0]
    except (OSError,IndexError): return None,None
if not p.exists():
    print('No managed background server is recorded. A legacy foreground session may still be running.')
    sys.exit(0)
try: info=json.loads(p.read_text()); pid=int(info['pid'])
except (ValueError,KeyError): sys.exit('Invalid server metadata; no process was signalled.')
token,state=identity(pid)
if token!=info['start_token'] or state=='Z':
    print('Recorded server is no longer active; metadata is stale. No process was signalled.')
    sys.exit(0)
if os.getpgid(pid)!=pid or info['directory']!=str(Path.cwd()):
    sys.exit('Process identity/group check failed; no process was signalled.')
if sys.argv[1]=='status':
    print(f"ACE process is running (PID {pid}, port {info['port']}, model {info['model']}).")
    print('This confirms the process, not model initialization or HTTP readiness.')
    sys.exit(0)
sig=signal.SIGKILL if sys.argv[1]=='kill' else signal.SIGTERM
os.killpg(pid,sig)
for _ in range(50):
    token,state=identity(pid)
    if token!=info['start_token'] or state=='Z': break
    time.sleep(.2)
else: sys.exit('Shutdown is still pending. Inspect --status/--logs; use --kill if required.')
print('Shutdown signal sent to the ACE process group.')
# Metadata is retained for safe stale detection; kernel lock is authoritative.
MANAGE
    exit 0
fi
case "$ACESTEP_MODEL" in
  acestep-v15-turbo|acestep-v15-sft|acestep-v15-base|acestep-v15-xl-turbo|acestep-v15-xl-sft|acestep-v15-xl-base) ;;
  *) fail 'Unsupported model. Use --help for the supported list.' ;;
esac
[[ "$gpu" =~ ^[0-9]+$ ]] || fail 'GPU index must be numeric.'
[[ "$ACESTEP_PORT" =~ ^[0-9]+$ ]] && (( ACESTEP_PORT >= 1 && ACESTEP_PORT <= 65535 )) || fail 'Invalid port.'
if [[ "$non_interactive" == true ]]; then
    [[ "$access_mode" != ask && "$auth_mode" != ask ]] || fail 'Non-interactive mode requires --local/--lan and --auth/--no-auth.'
    [[ "$auth_mode" != yes || -n "$password_file" ]] || fail 'Protected non-interactive mode requires --password-file.'
fi
supplied_password=
if [[ -n "$password_file" ]]; then
    [[ "$auth_mode" != no ]] || fail '--password-file cannot be combined with --no-auth.'
    [[ -f "$password_file" && -r "$password_file" ]] || fail 'Password file must be a readable regular file.'
    supplied_password=$(cat -- "$password_file")
    [[ -n "$supplied_password" && "$supplied_password" != *$'\n'* ]] || fail 'Password file must contain one nonempty password line.'
fi
if [[ "$access_mode" == ask ]]; then
    [[ -r /dev/tty ]] || fail 'Specify --local or --lan when no interactive terminal is available.'
    while true; do
        printf '\n Allow LAN browser access? [y/N]: ' >/dev/tty
        read -r access_answer </dev/tty || fail 'LAN selection cancelled.'
        case "$access_answer" in
            y|Y|yes|YES) bind=0.0.0.0; break ;;
            ''|n|N|no|NO) bind=127.0.0.1; break ;;
            *) printf ' Please answer yes or no.\n' >/dev/tty ;;
        esac
    done
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PATH="$HOME/.local/bin:$PATH"
command -v uv >/dev/null || fail 'uv is unavailable. Repair the installation first.'
command -v flock >/dev/null || fail 'flock is unavailable (Ubuntu util-linux package).'
command -v setsid >/dev/null || fail 'setsid is unavailable (Ubuntu util-linux package).'
[[ -f pyproject.toml && -x .venv/bin/python ]] || fail 'Incomplete ACE installation. Run the installer to repair it.'
models="${ACESTEP_CHECKPOINTS_DIR:-$PWD/checkpoints}"
[[ -f "$models/$ACESTEP_MODEL/config.json" && -f "$models/$ACESTEP_MODEL/model.safetensors" ]] || fail "Model $ACESTEP_MODEL is not downloaded. Download it before selecting it."

# flock is authoritative: kernel releases it on a crash. Never unlink its
# inode, which could allow competing processes to lock different files.
lock="$PWD/.ace-session.lock"
session="$PWD/.ace-session.info"
exec 9>"$lock"
if ! flock -n 9; then
    printf '\nACE already has an active launcher session.\n'
    [[ ! -f "$session" ]] || cat "$session"
    exit 1
fi
owns_lock=true
if [[ -f "$session" ]]; then
    printf '\nRecovered stale session metadata; the kernel lock is free.\n'
    cat "$session"
fi
# Detect a listener even if it was started without this launcher.
ACESTEP_BIND="$bind" uv run --no-sync python - <<'PORTCHECK'
import os,socket
s=socket.socket()
try: s.bind((os.environ['ACESTEP_BIND'],int(os.environ['ACESTEP_PORT'])))
except OSError as e: raise SystemExit(f'Port is unavailable: {e}. Stop the existing server or choose --port.')
finally: s.close()
PORTCHECK
printf 'Launcher PID: %s\nStarted: %s\nGPU: %s\nModel: %s\nPort: %s\n' "$$" "$(date -Is)" "$gpu" "$ACESTEP_MODEL" "$ACESTEP_PORT" > "$session"
chmod 600 "$session"
export CUDA_VISIBLE_DEVICES="$gpu"
export ACESTEP_BIND="$bind"
# Never reuse credentials inherited from a previous launch.
unset ACESTEP_BROWSER_USER ACESTEP_BROWSER_PASSWORD
while true; do
    if [[ "$auth_mode" == ask ]]; then
        [[ -r /dev/tty ]] || fail 'Specify --auth with --password-file, or --no-auth, when no terminal is available.'
        printf '\n Enable username/password browser protection? [Y/n]: ' >/dev/tty
        read -r auth_answer </dev/tty || fail 'Browser protection selection cancelled.'
        case "$auth_answer" in
            ''|y|Y|yes|YES) auth_mode=yes ;;
            n|N|no|NO) auth_mode=no ;;
            *) printf ' Please answer yes or no.\n' >/dev/tty; continue ;;
        esac
    fi
    if [[ "$auth_mode" == no ]]; then
        printf '\nStarting without browser login protection.\n'
        break
    fi
    if [[ -n "$supplied_password" ]]; then
        export ACESTEP_BROWSER_USER="${login_user_arg:-${USER:-ace}}"
        export ACESTEP_BROWSER_PASSWORD="$supplied_password"
        unset supplied_password
        printf '\nBrowser protection enabled.\n'
        break
    fi
    [[ -r /dev/tty ]] || fail 'A terminal or --password-file is required to enter credentials.'
    if [[ -n "$login_user_arg" ]]; then
        login_user="$login_user_arg"
    else
        printf '\n Browser login username [%s]: ' "${USER:-ace}" >/dev/tty
        read -r login_user </dev/tty || fail 'Login setup cancelled.'
        login_user="${login_user:-${USER:-ace}}"
    fi
    printf ' Browser login password (hidden): ' >/dev/tty
    read -rs login_password </dev/tty || fail 'Login setup cancelled.'
    printf '\n\n' >/dev/tty
    if [[ -z "$login_password" ]]; then
        printf ' Error: password cannot be blank. Choose whether to enable login again.\n\n' >/dev/tty
        auth_mode=ask
        continue
    fi
    export ACESTEP_BROWSER_USER="$login_user"
    export ACESTEP_BROWSER_PASSWORD="$login_password"
    unset login_password
    printf '\nBrowser protection enabled.\n'
    break
done
if [[ "$bind" != 127.0.0.1 ]]; then
    printf '\nBrowser: http://<host-LAN-IP>:%s\n\n' "$ACESTEP_PORT"
else
    printf '\nBrowser: http://127.0.0.1:%s (local or SSH tunnel)\n\n' "$ACESTEP_PORT"
fi
log="$PWD/ace-server.log"
if [[ "$foreground" == false ]]; then
    printf '\nStarting ACE in background. Log: %s\n' "$log"
    # Protect potentially sensitive user prompts/lyrics written by ACE logs.
    (umask 077; touch "$log")
    chmod 600 "$log"
fi
# Child inherits the kernel lock: even if launcher dies, a surviving server
# prevents another launcher from starting. Supervisor cleans metadata on exit.
# A detached session survives SSH disconnection; redirect output away from terminal.
# Foreground mode uses the same process group, supervised by this shell.
if [[ "$foreground" == true ]]; then exec 7>&1; else exec 7>>"$log"; fi
setsid uv run --no-sync python - >&7 2>&1 <<'PYACE' &
import ast
import os
from pathlib import Path
import shutil
import sys
import torch

if not torch.cuda.is_available():
    sys.exit('ERROR: CUDA is unavailable. Check your NVIDIA driver.')
major, minor = torch.cuda.get_device_capability(0)
if major < 7 or (major == 7 and minor < 5):
    sys.exit('ERROR: This launcher requires Turing (7.5) or newer.')
# Turing supports FP16, but this ACE model has overflowed in FP16.
# Pre-Ampere therefore defaults to FP32; newer cards use native BF16.
dtype = os.environ.get('ACESTEP_DTYPE', '').strip().lower()
if dtype == 'auto' or not dtype:
    dtype = 'float32' if major < 8 else 'bfloat16'
if dtype not in ('float32', 'float16', 'bfloat16'):
    sys.exit('ERROR: ACESTEP_DTYPE must be float32, float16, or bfloat16.')
if dtype == 'bfloat16' and major < 8:
    sys.exit('ERROR: This GPU does not support native BF16. Use float32.')
os.environ['ACESTEP_DTYPE'] = dtype

# Fix the known upstream fallback which otherwise ignores ACESTEP_DTYPE.
# Handle both the original assignment and our earlier FP32 repair.
path = Path('acestep/core/generation/handler/init_service_orchestrator.py')
source = path.read_text()
marker = '# ACE launcher: honor explicit dtype override'
if marker not in source:
    old_patch = ('self.dtype = (torch.float32 if os.environ.get("ACESTEP_DTYPE", "").strip().lower() '
                 '== "float32" else torch.float16)')
    old = old_patch if old_patch in source else 'self.dtype = torch.float16'
    if source.count(old) != 1:
        sys.exit('ERROR: Precision-selection code differs from the supported version. No patch applied; share this file for review.')
    tree = ast.parse(source)
    if not any(isinstance(n, ast.Import) and any(a.name == 'os' and a.asname is None for a in n.names) for n in tree.body):
        sys.exit('ERROR: Expected os import missing. No patch applied.')
    source = source.replace(old, 'self.dtype = torch.float32 if os.environ.get("ACESTEP_DTYPE") == "float32" else torch.float16', 1)
    needle = '            self.quantization = normalized_quantization'
    if source.count(needle) != 1:
        sys.exit('ERROR: Initialization structure differs. No patch applied.')
    override = '''            # ACE launcher: honor explicit dtype override
            if resolved_device == "cuda" and os.environ.get("ACESTEP_DTYPE"):
                self.dtype = getattr(torch, os.environ["ACESTEP_DTYPE"])
                logger.info(f"[initialize_service] Explicit dtype override: {self.dtype}")
'''
    source = source.replace(needle, override + needle, 1)
    compile(source, str(path), 'exec')
    backup = path.with_name(path.name + '.before-auto-dtype')
    if backup.exists():
        sys.exit(f'ERROR: Backup {backup} already exists and patch is absent. Inspect before retrying.')
    shutil.copy2(path, backup)
    path.write_text(source)
    print(f'Precision override installed; original backed up to {backup}', flush=True)

#!/usr/bin/env python3
"""Guard Flow Edit's final conditioning call with the model load context."""
import ast
from pathlib import Path
import shutil
import sys

path = Path('acestep/core/generation/handler/service_generate_flow_edit.py')
if not path.is_file():
    sys.exit('ERROR: Run from your ACE-Step installation directory.')
source = path.read_text()
marker = '# ACE launcher: keep conditioning model on the active device'
if marker in source:
    print('Flow Edit offload patch already installed.')
else:
    tree = ast.parse(source)
    parents = {child: parent for parent in ast.walk(tree) for child in ast.iter_child_nodes(parent)}
    matches = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign) or not isinstance(node.value, ast.Call):
            continue
        fn = node.value.func
        if (isinstance(fn, ast.Attribute) and fn.attr == 'prepare_condition'
                and isinstance(fn.value, ast.Attribute) and fn.value.attr == 'model'
                and isinstance(fn.value.value, ast.Name) and fn.value.value.id == 'handler'):
            matches.append(node)
    if len(matches) != 1:
        sys.exit('ERROR: Expected one conditioning call. Source differs; no changes made.')
    node = matches[0]
    ancestor = parents.get(node)
    guarded = False
    while ancestor is not None:
        if isinstance(ancestor, ast.With):
            for item in ancestor.items:
                call = item.context_expr
                if (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                        and call.func.attr == '_load_model_context'
                        and call.args and isinstance(call.args[0], ast.Constant)
                        and call.args[0].value == 'model'):
                    guarded = True
        ancestor = parents.get(ancestor)
    if guarded:
        print('Conditioning call already guarded by upstream; no changes needed.')
    else:
        lines = source.splitlines(keepends=True)
        indent = ' ' * node.col_offset
        block = lines[node.lineno-1:node.end_lineno]
        lines[node.lineno-1:node.end_lineno] = [indent + marker + '\n',
            indent + 'with handler._load_model_context("model"):\n'] + ['    '+line for line in block]
        updated = ''.join(lines)
        compile(updated, str(path), 'exec')
        backup = path.with_name(path.name + '.before-offload-fix')
        if backup.exists():
            sys.exit(f'ERROR: Backup already exists: {backup}. No files changed.')
        shutil.copy2(path, backup)
        path.write_text(updated)
        print(f'Fixed model placement for Flow Edit conditioning. Backup: {backup}')

probe = torch.ones((64, 64), device='cuda', dtype=getattr(torch, dtype))
if not torch.isfinite(probe @ probe).all().item():
    sys.exit('ERROR: GPU precision test failed.')
del probe
torch.cuda.empty_cache()
print(f'GPU: {torch.cuda.get_device_name(0)}; capability {major}.{minor}; selected {dtype}', flush=True)
offload = 'true' if dtype == 'float32' else 'false'
sys.argv = ['acestep', '--config_path', os.environ['ACESTEP_MODEL'], '--device', 'cuda',
            '--backend', 'pt', '--init_llm', 'false', '--use_flash_attention', 'false',
            '--quantization', 'none', '--offload_to_cpu', offload,
            '--offload_dit_to_cpu', offload, '--batch_size', '1', '--init_service', 'true',
            '--server-name', os.environ['ACESTEP_BIND'], '--port', os.environ['ACESTEP_PORT']]
if os.environ.get('ACESTEP_BROWSER_PASSWORD'):
    # Password never appears in the shell command/process argument list.
    sys.argv += ['--auth-username', os.environ['ACESTEP_BROWSER_USER'],
                 '--auth-password', os.environ['ACESTEP_BROWSER_PASSWORD']]
from acestep.acestep_v15_pipeline import main
main()
PYACE
child=$!
printf 'Server process: %s\n' "$child" >> "$session"
# Record Linux process start time to prevent signalling a recycled PID.
.venv/bin/python - "$child" <<'RECORD'
import json,os,sys,time
from pathlib import Path
pid=int(sys.argv[1])
for _ in range(100):
    try:
        fields=Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()
        if os.getpgid(pid)==pid: break
    except OSError: pass
    time.sleep(.02)
else: raise SystemExit('Server exited before its process identity could be recorded. Check ace-server.log.')
info={'pid':pid,'start_token':fields[19], 'directory':str(Path.cwd()),
      'port':os.environ['ACESTEP_PORT'],'model':os.environ['ACESTEP_MODEL']}
p=Path('.ace-server.json');tmp=p.with_suffix('.tmp')
tmp.write_text(json.dumps(info));tmp.chmod(0o600);tmp.replace(p)
RECORD
if [[ "$foreground" == false ]]; then
    # Child now owns the inherited lock. Parent exits without stopping it.
    child=''
    owns_lock=false
    exec 9>&-
    exec 7>&-
    printf '\nACE launched. Initialization continues in the background.\n'
    printf 'Check: start-ace --status\nLogs: start-ace --logs\nStop: start-ace --stop\nForce: start-ace --kill\n'
    exit 0
fi
wait "$child"
child=''
LAUNCHER
chmod +x start-ace.sh
# Preserve the selected physical GPU index for future launches.
printf -v quoted_index '%q' "$GPU_INDEX"
sed -i "s/ACESTEP_GPU_INDEX:-0/ACESTEP_GPU_INDEX:-${quoted_index}/" start-ace.sh
printf '\nInstallation complete. Start with:\n  %q\n' "$INSTALL_DIR/start-ace.sh"
printf 'Startup asks for LAN access (default no) and browser protection (default yes).\n'
printf 'For SSH tunneling: run start-ace.sh --local\n'
printf 'Models and GPU precision are initialized when you launch. No service, firewall rule, or reverse proxy was installed.\n'

# Install/repair finished successfully; optional shell convenience setup.
if ask 'Add the ACE directory to PATH and create the start-ace alias in your shell profile?'; then
    login_shell="${SHELL:-/bin/bash}"
    case "$(basename "$login_shell")" in
        bash) profile="$HOME/.bashrc" ;;
        zsh) profile="${ZDOTDIR:-$HOME}/.zshrc" ;;
        *) profile=''; printf '\nAutomatic profile setup supports Bash and Zsh. No profile changed.\n' ;;
    esac
    if [[ -n "$profile" ]]; then
        export ACE_INSTALL_PROFILE="$profile" ACE_INSTALL_DIRECTORY="$INSTALL_DIR"
        uv run --no-sync python - <<'PROFILE'
import os, shlex, shutil, time
from pathlib import Path
p=Path(os.environ['ACE_INSTALL_PROFILE'])
p.parent.mkdir(parents=True,exist_ok=True)
s=p.read_text() if p.exists() else ''
begin='# >>> ACE-Step shell setup >>>'
end='# <<< ACE-Step shell setup <<<'
if s.count(begin)!=s.count(end) or s.count(begin)>1:
    raise SystemExit('Profile markers are ambiguous; profile not changed.')
if begin in s:
    a=s.index(begin); b=s.index(end,a)+len(end)
    s=s[:a]+s[b:]
directory=os.environ['ACE_INSTALL_DIRECTORY']
block=(begin+'\nexport PATH='+shlex.quote(directory)+':"$PATH"\n'
       +'alias start-ace='+shlex.quote(shlex.quote(directory+'/start-ace.sh'))+'\n'+end+'\n')
if p.exists(): shutil.copy2(p,p.with_name(p.name+'.ace-backup.'+str(time.time_ns())))
p.write_text(s.rstrip()+'\n\n'+block)
print('Shell profile updated:',p)
print('Open a new shell, or source this profile, to use start-ace.')
PROFILE
    fi
fi
# Release repair lock before optionally starting the launcher.
if [[ "$resume" == true ]]; then flock -u 8; exec 8>&-; fi
if ask 'Start ACE now?'; then
    if bash "$INSTALL_DIR/start-ace.sh"; then
        printf '\nACE session ended. Installation remains complete.\n'
    else
        printf '\nACE startup/session ended with an error. Installation completed successfully; no reinstall is needed for an empty login password.\n' >&2
    fi
fi
