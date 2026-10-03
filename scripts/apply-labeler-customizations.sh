#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="\$(cd -- "\$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

: "${APP_DIR}"
LABELER_DID="${ESPELUNCA_LABELER_DID:-}"

cd "${APP_DIR}"

python3 - "${LABELER_DID}" <<'PY'
from pathlib import Path
import sys

labeler_did = sys.argv[1].strip()
target = Path("src/state/session/create-account.ts")
text = target.read_text()

if "const ESPELUNCA_LABELER_DID =" in text:
    start = text.index("const ESPELUNCA_LABELER_DID = ")
    end = text.index("\n", start)
    text = text[:start] + f"const ESPELUNCA_LABELER_DID = {labeler_did!r}" + text[end:]
else:
    anchor = "import {type SessionAccount} from './types'\n"
    if anchor not in text:
        raise SystemExit("Ponto de inserção do Labeler não encontrado.")
    text = text.replace(
        anchor,
        anchor + f"\nconst ESPELUNCA_LABELER_DID = {labeler_did!r}\n",
        1,
    )

old_import = "import {overwriteSavedFeeds, setPersonalDetails, upsertProfile} from '@bsky/sdk'"
new_import = "import {addLabeler, overwriteSavedFeeds, setPersonalDetails, upsertProfile} from '@bsky/sdk'"
if old_import in text:
    text = text.replace(old_import, new_import, 1)

if "type DidString" not in text:
    text = text.replace(
        "import {toDatetimeString} from '@atproto/syntax'\n",
        "import {toDatetimeString, type DidString} from '@atproto/syntax'\n",
        1,
    )

old_moderation = "import {configureModerationForAccount} from './moderation'"
new_moderation = "import {configureModerationForAccount, saveLabelers} from './moderation'"
if old_moderation in text:
    text = text.replace(old_moderation, new_moderation, 1)

old_configure = "  configureModerationForAccount(bundle, earlyAccount)\n"
new_configure = """  if (ESPELUNCA_LABELER_DID) {
    saveLabelers(accountDid, [ESPELUNCA_LABELER_DID])
  }
  configureModerationForAccount(bundle, earlyAccount)
"""
if new_configure not in text:
    if old_configure not in text:
        raise SystemExit("configureModerationForAccount não encontrado.")
    text = text.replace(old_configure, new_configure, 1)

old_tasks = """  const postSignupTasks: Promise<unknown>[] = [
    savePersonalDetails(pdsClient, birthDate),
    initializeProfile(pdsClient, {handle, createdAt, isProd}),
  ]
"""
new_tasks = old_tasks + """  if (ESPELUNCA_LABELER_DID) {
    postSignupTasks.push(initializeEspeluncaLabeler(pdsClient))
  }
"""
if new_tasks not in text:
    if old_tasks not in text:
        raise SystemExit("Lista de tarefas pós-cadastro não encontrada.")
    text = text.replace(old_tasks, new_tasks, 1)

if "function initializeEspeluncaLabeler(client: Client)" not in text:
    anchor = "function initializeSavedFeeds(client: Client) {\n"
    function_code = """function initializeEspeluncaLabeler(client: Client) {
  if (!ESPELUNCA_LABELER_DID) return Promise.resolve()
  return retryPostSignupTask(
    'subscribe to the Espelunca moderation labeler',
    3,
    () => client.call(addLabeler, ESPELUNCA_LABELER_DID as DidString),
  )
}

"""
    if anchor not in text:
        raise SystemExit("initializeSavedFeeds não encontrado.")
    text = text.replace(anchor, function_code + anchor, 1)

target.write_text(text)
PY

echo "Customização do Labeler aplicada. DID: ${LABELER_DID:-não configurado}"
