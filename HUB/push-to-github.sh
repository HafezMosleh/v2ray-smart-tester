#!/usr/bin/env bash
set -euo pipefail

# This script safely pushes changes for THIS repository via GitHub API
# It bypasses standard git ports (22, 443) which might be blocked on this server

PROJECT_NAME="v2ray-smart-tester"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

origin_url="$(git remote get-url origin 2>/dev/null || echo 'https://github.com/HafezMosleh/v2ray-smart-tester.git')"
branch="$(git branch --show-current 2>/dev/null || echo 'main')"
if [ -z "$branch" ]; then branch="main"; fi

git add -A
if git diff --cached --quiet; then
  echo "No changes to push for $PROJECT_NAME."
  exit 0
fi

commit_message="update $PROJECT_NAME files via API push"
git -c user.name="HUB Auto Push" -c user.email="hub@local" commit -m "$commit_message" >/dev/null 2>&1 || true

echo "Pushing changes for $PROJECT_NAME..."

python3 - "$PROJECT_NAME" "$origin_url" "$branch" "$commit_message" <<'PY'
import base64, json, os, re, subprocess, sys, time, urllib.error, urllib.request
project_name, origin_url, branch, commit_message = sys.argv[1:5]
owner, repo = "HafezMosleh", project_name

token = subprocess.check_output(['gh', 'auth', 'token'], text=True).strip()
headers = {
    'Authorization': f'Bearer {token}',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'python-api-pusher'
}

def api(method, path, data=None):
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request('https://api.github.com' + path, data=body, method=method, headers=headers)
    if data: req.add_header('Content-Type', 'application/json')
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as exc:
            if exc.code in (403, 429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2)
                continue
            raise SystemExit(f'API Error {exc.code}')
        except Exception:
            if attempt < 3:
                time.sleep(2)
                continue
            raise

try:
    ref = api('GET', f'/repos/{owner}/{repo}/git/ref/heads/{branch}')
    parent_sha = ref['object']['sha']
    base_tree = api('GET', f'/repos/{owner}/{repo}/git/commits/{parent_sha}')['tree']['sha']
except Exception as e:
    print(f"Failed to fetch branch {branch}: {e}")
    sys.exit(1)

changed = subprocess.check_output(['git', 'diff-tree', '--no-commit-id', '--name-status', '-r', 'HEAD'], text=True).splitlines()
tree = []
for line in changed:
    parts = line.split('\t')
    status, path = parts[0], parts[-1]
    if status.startswith('D'):
        tree.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': None})
        continue
    if not os.path.isfile(path): continue
    if os.path.getsize(path) > 50 * 1024 * 1024:
        raise SystemExit(f'File too large: {path}')
        
    with open(path, 'rb') as handle:
        content = base64.b64encode(handle.read()).decode()
    blob_sha = api('POST', f'/repos/{owner}/{repo}/git/blobs', {'content': content, 'encoding': 'base64'})['sha']
    mode = '100755' if os.access(path, os.X_OK) else '100644'
    tree.append({'path': path, 'mode': mode, 'type': 'blob', 'sha': blob_sha})

if not tree:
    raise SystemExit('No files found to upload.')

new_tree = api('POST', f'/repos/{owner}/{repo}/git/trees', {'base_tree': base_tree, 'tree': tree})['sha']
new_commit = api('POST', f'/repos/{owner}/{repo}/git/commits', {'message': commit_message, 'tree': new_tree, 'parents': [parent_sha]})['sha']
api('PATCH', f'/repos/{owner}/{repo}/git/refs/heads/{branch}', {'sha': new_commit, 'force': False})
print(f'✅ Successfully pushed {project_name}')
PY
