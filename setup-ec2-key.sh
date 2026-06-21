#!/usr/bin/env bash
set -euo pipefail

KEY_FILE="ec2-key.pem"
SSH_DIR="${HOME}/.ssh"
KEY_PATH="${SSH_DIR}/${KEY_FILE}"
PLATFORM=""

prompt_platform() {
  while true; do
    echo "Which machine are you using?"
    echo "  1) Mac"
    echo "  2) Linux / WSL"
    read -r -p "Enter 1 or 2: " choice

    case "${choice}" in
      1 | mac | Mac | MAC)
        PLATFORM="mac"
        return 0
        ;;
      2 | linux | Linux | wsl | WSL)
        PLATFORM="linux"
        return 0
        ;;
      *)
        echo "Invalid choice. Please enter 1 or 2."
        ;;
    esac
  done
}

ensure_ssh_dir() {
  cd "${HOME}"
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
}

key_exists() {
  [[ -f "${KEY_PATH}" ]]
}

remove_existing_key() {
  ssh-add -d "${KEY_PATH}" >/dev/null 2>&1 || true
  rm -f "${KEY_PATH}" "${KEY_PATH}.pub"
}

prompt_yes_no() {
  local prompt_text="$1"
  local answer=""

  while true; do
    read -r -p "${prompt_text} (yes/no): " answer
    case "${answer}" in
      yes | y | Y)
        return 0
        ;;
      no | n | N)
        return 1
        ;;
      *)
        echo "Please answer yes or no."
        ;;
    esac
  done
}

read_private_key() {
  local tmp_file
  local line
  tmp_file="$(mktemp)"

  echo
  echo "Paste the private SSH key content for ${KEY_FILE}."
  echo "When you are done, press Enter:"
  echo

  while IFS= read -r line; do
    [[ -z "${line}" ]] && break
    printf '%s\n' "${line}" >>"${tmp_file}"
  done

  if [[ ! -s "${tmp_file}" ]]; then
    rm -f "${tmp_file}"
    echo "No key content provided." >&2
    exit 1
  fi

  if ! grep -q "BEGIN.*PRIVATE KEY" "${tmp_file}" || ! grep -q "END.*PRIVATE KEY" "${tmp_file}"; then
    rm -f "${tmp_file}"
    echo "That does not look like a valid private key (expected BEGIN/END PRIVATE KEY markers)." >&2
    exit 1
  fi

  mv "${tmp_file}" "${KEY_PATH}"
  chmod 600 "${KEY_PATH}"
}

add_key_to_agent() {
  if [[ "${PLATFORM}" == "mac" ]]; then
    if ssh-add --apple-use-keychain "${KEY_PATH}"; then
      echo "Added ${KEY_FILE} to the SSH agent and macOS keychain."
    else
      echo "Failed to add ${KEY_FILE} to the SSH agent/keychain." >&2
      exit 1
    fi
    return 0
  fi

  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    eval "$(ssh-agent -s)" >/dev/null
  fi

  if ssh-add "${KEY_PATH}"; then
    echo "Added ${KEY_FILE} to the SSH agent."
  else
    echo "Failed to add ${KEY_FILE} to the SSH agent." >&2
    exit 1
  fi
}

main() {
  prompt_platform
  ensure_ssh_dir

  if key_exists; then
    echo "An SSH key named ${KEY_FILE} already exists at ${KEY_PATH}."
    if prompt_yes_no "Delete the existing key and replace it"; then
      remove_existing_key
    else
      echo "Leaving the existing ${KEY_FILE} key in place."
      exit 0
    fi
  fi

  read_private_key
  add_key_to_agent

  echo
  echo "Done. Private key: ${KEY_PATH}"
}

main "$@"
