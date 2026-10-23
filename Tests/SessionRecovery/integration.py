"""Real launchd recovery with isolated preferences; never edits menu visibility."""
import os, pathlib, plistlib, shutil, subprocess, tempfile, time
helper = pathlib.Path('.build/HidecellSessionTests').resolve()
label = 'app.hidecell.recovery-test'
fixture = [{'bundle': {'_0': 'example.visible'}}, {'isAllowed': True, 'metadata': 'keep'}, {'bundle': {'_0': 'example.alreadyHidden'}}, {'isAllowed': False}]
def rows(domain):
    obj = plistlib.loads(subprocess.check_output(['defaults','export',domain,'-']))
    return plistlib.loads(obj['trackedApplications'])
def wait_for(check):
    end=time.monotonic()+15
    while time.monotonic()<end:
        if check(): return
        time.sleep(.1)
    raise AssertionError('timed out')
for case in ['quit','main-killed','both-killed','uninstall-and-preferences-deleted']:
    with tempfile.TemporaryDirectory(prefix='hidecell-session-test-') as temp:
        root=pathlib.Path(temp); domain=str(root/'preferences'); binary=root/'Hidecell'; shutil.copy2(helper,binary)
        subprocess.run(['defaults','write',domain,'trackedApplications','-data',plistlib.dumps(fixture,fmt=plistlib.FMT_BINARY).hex()],check=True)
        p=subprocess.Popen([str(binary)],env=dict(os.environ,HIDECELL_TEST_DOMAIN=domain),stdout=subprocess.PIPE)
        try:
            assert p.stdout.readline().strip()==b'READY'
            assert rows(domain)[1]['isAllowed'] is False
            if case=='quit': p.terminate()
            elif case=='main-killed': p.kill()
            elif case=='both-killed':
                subprocess.run(['launchctl','kill','SIGKILL',f'gui/{os.getuid()}/{label}'],check=True)
                p.kill()
            else:
                subprocess.run(['defaults','delete',domain+'.recovery'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                binary.unlink()
            p.wait(timeout=10)
            wait_for(lambda: rows(domain)==fixture)
            wait_for(lambda: not pathlib.Path(domain+'.session').exists())
            time.sleep(.3)
            assert subprocess.run(['launchctl','print',f'gui/{os.getuid()}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode != 0
            print('PASS:',case,flush=True)
        finally:
            if p.poll() is None: p.kill(); p.wait()
            subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
