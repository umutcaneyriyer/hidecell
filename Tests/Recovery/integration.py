"""Exercise the real guardian against isolated preference domains, never the menu bar."""
import json, os, pathlib, plistlib, shutil, signal, subprocess, sys, tempfile, time

helper = str(pathlib.Path('.build/HidecellRecoveryTests').resolve())
def export(domain):
    return plistlib.loads(subprocess.check_output(['defaults', 'export', domain, '-']))
def write(domain, key, value):
    subprocess.run(['defaults', 'write', domain, key, '-data', plistlib.dumps(value, fmt=plistlib.FMT_BINARY).hex()], check=True)
def rows(domain): return plistlib.loads(export(domain)['trackedApplications'])
def await_restore(domain):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        r = rows(domain)
        if r[1]['isAllowed'] is True and r[3]['isAllowed'] is False:
            assert r[1]['metadata'] == 'keep'
            assert r[5]['isAllowed'] is True
            return
        time.sleep(.1)
    raise AssertionError('guardian did not restore original visibility')
fixture = [
 {'bundle': {'_0': 'example.visible'}}, {'isAllowed': True, 'metadata': 'keep'},
 {'bundle': {'_0': 'example.alreadyHidden'}}, {'isAllowed': False},
 {'bundle': {'_0': 'example.unrelated'}}, {'isAllowed': True}]
for scenario in ['channel-close', 'bundle-removal', 'parent-sigkill', 'preferences-removal', 'guardian-sigterm']:
    with tempfile.TemporaryDirectory(prefix='hidecell-recovery-test-') as temp:
        root=pathlib.Path(temp); bundle=root/'Hidecell.app';bundle.mkdir()
        domain=str(root/'controlcenter')
        write(domain,'trackedApplications',fixture)
        subprocess.run(['defaults','write',domain,'unrelated-setting','-string','untouched'],check=True)
        env=dict(os.environ,HIDECELL_TEST_DOMAIN=domain)
        command=json.dumps(['example.visible','example.alreadyHidden']).encode()+b'\n'
        if scenario=='parent-sigkill':
            parent_code='''import subprocess,sys,time
p=subprocess.Popen(sys.argv[1:],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
p.stdin.write(%r);p.stdin.flush()
assert p.stdout.read(1)==b'\\x01'
print(p.pid,flush=True)
time.sleep(30)
''' % command
            parent=subprocess.Popen([sys.executable,'-c',parent_code,helper,str(bundle)],stdout=subprocess.PIPE,env=env)
            guardian_pid=int(parent.stdout.readline());assert rows(domain)[1]['isAllowed'] is False
            parent.kill();parent.wait()
        else:
            child=subprocess.Popen([helper,str(bundle)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,env=env)
            child.stdin.write(command);child.stdin.flush();assert child.stdout.read(1)==b'\x01'
            assert rows(domain)[1]['isAllowed'] is False
            if scenario=='guardian-sigterm': child.terminate()
            elif scenario=='bundle-removal': shutil.rmtree(bundle)
            elif scenario=='preferences-removal':
                # Delete the test executable's preferences after hiding. Recovery must use memory.
                subprocess.run(['defaults','delete',domain+'.recovery'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                shutil.rmtree(bundle)
            else: child.stdin.close()
        await_restore(domain)
        assert export(domain)['unrelated-setting']=='untouched'
        if scenario!='parent-sigkill':
            assert child.wait(timeout=8)==0
        print('PASS:',scenario)
print('5 recovery integration scenarios passed')
