#!/usr/bin/env bash
# Offline transport/checksum fixtures in scratch copies; production pins remain untouched.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import hashlib,os,re,subprocess,sys,tempfile,zipfile
repo=Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='vaultwarden-tool-downloads-') as temp:
    root=Path(temp);bin_dir=root/'bin';bin_dir.mkdir()
    shim=bin_dir/'curl'
    shim.write_text('''#!/usr/bin/env python3
from pathlib import Path
import os,shutil,sys
args=sys.argv[1:];dest=Path(args[args.index('--output')+1])
state=Path(os.environ['VW_TOOL_FIXTURE_STATE'])
count=int(state.read_text())+1 if state.exists() else 1
state.write_text(str(count))
mode=os.environ['VW_TOOL_FIXTURE_MODE']
if mode=='all-fail' or (mode=='fallback' and count==1):
    dest.write_bytes(b'partial transfer');sys.exit(56)
if mode=='all-corrupt' or (mode=='checksum-fallback' and count==1):
    dest.write_bytes(b'not the pinned archive');sys.exit(0)
shutil.copyfile(os.environ['VW_TOOL_FIXTURE_ARCHIVE'],dest)
''');shim.chmod(0o755)
    for tool in ['xcodegen','swiftformat']:
        source=(repo/'Scripts'/f'{tool}.sh').read_text()
        version=re.search(r'^VERSION="([^"]+)"',source,re.M)[1]
        output=f'Version: {version}' if tool=='xcodegen' else version
        archive=root/f'{tool}.zip'
        entry='xcodegen/bin/xcodegen' if tool=='xcodegen' else 'swiftformat'
        executable='#!/bin/sh\nprintf executed >> "$VW_TOOL_FIXTURE_EXECUTED"\nprintf "%s\\n" "'+output+'"\n'
        with zipfile.ZipFile(archive,'w') as z:
            info=zipfile.ZipInfo(entry);info.create_system=3;info.external_attr=0o100755<<16
            z.writestr(info,executable)
        digest=hashlib.sha256(archive.read_bytes()).hexdigest()
        for mode in ['primary','fallback','checksum-fallback','all-fail','all-corrupt']:
            fixture=root/f'{tool}-{mode}';(fixture/'Scripts').mkdir(parents=True)
            # Only this scratch copy trusts the synthetic archive, never the real wrapper.
            text,n=re.subn(r'^ZIP_SHA256="[0-9a-f]+"',f'ZIP_SHA256="{digest}"',source,count=1,flags=re.M)
            assert n==1
            script=fixture/'Scripts'/f'{tool}.sh';script.write_text(text)
            state=fixture/'calls';executed=fixture/'executed'
            env=os.environ.copy();env.update(PATH=str(bin_dir)+os.pathsep+env['PATH'],VW_TOOL_FIXTURE_STATE=str(state),VW_TOOL_FIXTURE_MODE=mode,VW_TOOL_FIXTURE_ARCHIVE=str(archive),VW_TOOL_FIXTURE_EXECUTED=str(executed))
            result=subprocess.run(['bash',str(script),'--version'],env=env,capture_output=True,text=True)
            cache=fixture/'.build/tools'/f'{tool}-{version}'
            success=mode not in ['all-fail','all-corrupt']
            assert (result.returncode==0)==success,(tool,mode,result.stderr)
            assert int(state.read_text())==(1 if mode=='primary' else 2),(tool,mode)
            assert not list(cache.glob('download.*')),(tool,mode,'partial archive retained')
            if success:
                assert (cache/f'{tool}.zip').read_bytes()==archive.read_bytes()
                assert executed.exists() and output in result.stdout
            else:
                assert not (cache/f'{tool}.zip').exists() and not executed.exists()
            print(f'{tool}: {mode} passed')
print('Tool download fixtures passed; fallback and checksum failures cannot execute partial/unverified archives.')
PY
