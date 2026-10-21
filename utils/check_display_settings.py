#!/usr/bin/env python3
"""Isolated display safety/layout checks; never changes the desktop or clipboard."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
from unittest.mock import patch

import display_settings as d

connected = [dict(name='eDP-1', width=1920, height=1080, refreshRate=60.03, scale=1, transform=0,
                  x=0, y=0, disabled=False, mirrorOf='none', availableModes=['1920x1080@60.03Hz']),
             dict(name='HDMI-A-1', width=2560, height=1440, refreshRate=59.95, scale=1, transform=0,
                  x=1920, y=0, disabled=False, mirrorOf='none', availableModes=['2560x1440@59.95Hz'])]
original = d.snapshot(connected)
assert d.validate(original, connected) == original
for changes in (
    {'name': 'bad";os.execute("false")'}, {'scale': float('nan')}, {'scale': .1},
    {'x': 1.5}, {'x': 40000}, {'transform': 8}, {'mode': '8000x8000@144'},
    {'mirror': 'eDP-1'}, {'enabled': 1},
):
    invalid = copy.deepcopy(original); invalid[0].update(changes)
    try: d.validate(invalid, connected)
    except (ValueError, TypeError): pass
    else: raise AssertionError(('Invalid input accepted', changes))
for invalid in (
    [dict(m, enabled=False) for m in original],
    [dict(original[0], mirror='HDMI-A-1'), dict(original[1], mirror='eDP-1')],
    [dict(original[0], enabled=False), dict(original[1], mirror='eDP-1')],
    original[:1],
):
    try: d.validate(invalid, connected)
    except ValueError: pass
    else: raise AssertionError('Disabled desktop, mirror cycle or stale topology accepted')

with tempfile.TemporaryDirectory() as folder:
    runtime = Path(folder)
    configuration = runtime/'config/monitor-overrides.tsv'
    configuration.parent.mkdir()
    configuration.write_text('DP-9\tpreferred\tauto\t1\t0\n')
    with patch.multiple(d, RUNTIME=runtime, CONFIG=configuration), patch.object(d.signal, 'signal'):
        for mode in ('timeout', 'confirm', 'revert', 'apply-error', 'save-error'):
            token = 'a'*32
            applied = []
            changed = copy.deepcopy(original); changed[1]['x'] = 2000
            def apply(items):
                applied.append(copy.deepcopy(items))
                if mode == 'apply-error' and len(applied) == 1:
                    raise RuntimeError('Display refused mode')
            def publish(value):
                if value['phase'] == 'pending' and mode in ('confirm','revert','save-error'):
                    d.atomic(runtime/(token+'.decision'), 'confirm' if mode != 'revert' else 'revert')
            previous = configuration.read_bytes()
            with patch.object(d, 'monitors', return_value=connected), patch.object(d, 'apply', side_effect=apply), \
                 patch.object(d, 'verify'), patch.object(d, 'publish', side_effect=publish) as events, \
                 patch.object(d.time, 'sleep'), patch.object(d, 'TIMEOUT', 0 if mode == 'timeout' else 15):
                if mode == 'save-error':
                    with patch.object(d, 'save', side_effect=OSError('Disk full')):
                        d.guard(token, changed)
                else:
                    d.guard(token, changed)
                final = events.call_args.args[0]
            if mode == 'confirm':
                assert len(applied) == 1 and final['phase'] == 'saved'
                assert configuration.read_text().startswith('DP-9\t')
                assert 'HDMI-A-1\t2560x1440@59.950\t2000x0\t1\t0\t1\t' in configuration.read_text()
            else:
                assert applied[-1] == original, (mode, applied)
                assert configuration.read_bytes() == previous, mode
                assert final['phase'] == ('error' if mode in ('apply-error','save-error') else 'reverted')
            assert not (runtime/(token+'.decision')).exists()

        commands=[]
        with patch.object(d, 'run', side_effect=lambda *args: commands.append(args)):
            d.apply([dict(original[0], enabled=False), dict(original[1], mirror='')])
        lua=commands[0][2]
        assert lua.index('HDMI-A-1') < lua.index('eDP-1')
        assert 'disabled=true' in lua and 'disabled=false' in lua

        with patch.object(d, 'monitors', return_value=[connected[0]]), patch.object(d, 'apply') as apply:
            d.rollback([dict(original[0], enabled=False), original[1]])
            restored=apply.call_args.args[0]
            assert len(restored)==1 and restored[0]['enabled'] and restored[0]['mode']=='preferred'

        d.publish({'token':'b'*32, 'phase':'pending', 'deadline':0})
        try: d.main(['confirm','b'*32])
        except ValueError: pass
        else: raise AssertionError('Expired preview accepted')

        # Execute the actual login parser against old and new TSV rows.
        configuration = runtime/'.config/caelestia/monitor-overrides.tsv'
        configuration.parent.mkdir(parents=True)
        configuration.write_text('DP-9\tpreferred\tauto\t1\t0\neDP-1\t1920x1080@60.03\t0x0\t1\t0\t0\t\nHDMI-A-1\t2560x1440@59.95\t1920x0\t1\t1\t1\tDP-9\n')
        parser = (Path.home()/'.config/hypr/hyprland.lua').read_text().split('local monitor_overrides =',1)[1].split('-- Configs',1)[0]
        lua = 'local home = ' + json.dumps(str(runtime)) + '; local rows={}; hl={monitor=function(row) rows[#rows+1]=row end};\nlocal monitor_overrides =' + parser + '''
assert(#rows==3)
assert(rows[1].output=='DP-9' and rows[1].disabled==false and rows[1].mirror==nil)
assert(rows[2].output=='eDP-1' and rows[2].disabled==true and rows[2].mirror==nil)
assert(rows[3].output=='HDMI-A-1' and rows[3].mirror=='DP-9' and rows[3].transform==1)
'''
        subprocess.run(['lua','-e',lua],check=True)

layout = Path(__file__).parent.parent/'modules/nexus/pages/DisplayLayout.js'
js = layout.read_text().replace('.pragma library', '') + '''
const assert = require('node:assert/strict');
const a = fromMonitor({name:'eDP-1',width:1920,height:1080,refreshRate:60,scale:1,transform:0,x:0,y:0,availableModes:['1920x1080@60Hz']});
const b = {...a,name:'HDMI-A-1',x:1920};
const rotated = {...b,transform:1,scale:1.5};
assert.deepEqual(geometry(rotated),{width:720,height:1280});
assert.deepEqual(preset([a,b],'internal').map(m=>m.enabled),[true,false]);
assert.deepEqual(preset([a,b],'external').map(m=>m.enabled),[false,true]);
assert.deepEqual(preset([a,b],'mirror').map(m=>m.mirror),['','eDP-1']);
const extend=preset([a,rotated],'extend');
assert.equal(extend[1].x,1920);
assert.deepEqual(bounds(extend),{x:0,y:0,width:2640,height:1280});
assert.deepEqual(snap([a,b],b.name,1910,12),{x:1920,y:0});
assert.equal(a.x,0); assert.equal(b.x,1920);
assert.deepEqual(Object.keys(payload([a])[0]).sort(),['enabled','mirror','mode','name','scale','transform','x','y']);
'''
subprocess.run(['node','-e',js],check=True)
print('PASS: input validation, mirror safety, timeout/revert, confirmed save, failure rollback, unplug recovery, layout/scale/rotation/snap')

if '--ui' in sys.argv:
    shell = Path(__file__).parent.parent
    qml = '''import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.services
import qs.modules.nexus as Nexus
import qs.modules.nexus.pages as Pages
ShellRoot {
    id: root
    property int stage: 0
    function check(value, message) { if (!value) throw new Error(message); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found=find(child,name); if(found) return found; }
        return null;
    }
    Nexus.NexusState { id: state; screen: Quickshell.screens[0]; isWindow: true }
    PanelWindow {
        id: win
        visible: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        implicitWidth: 850; implicitHeight: 850
        color: Colours.palette.m3surface
        contentItem.Config.screen: screen.name
        contentItem.Tokens.screen: screen.name
        Pages.DisplayPage { id: page; nState: state; anchors.fill: parent; anchors.margins: 24 }
    }
    Timer {
        interval: 1200; running: true
        onTriggered: {
            try {
                page.pollTimer.running=false; page.hyprEvents.enabled=false;
                const a={name:'eDP-1',description:'Dizüstü ekranı',focused:true,mode:'1920x1080@60.03',availableModes:['1920x1080@60.03'],x:0,y:0,scale:1,transform:0,enabled:true,mirror:''};
                const b={name:'HDMI-A-1',description:'Harici ekran',focused:false,mode:'2560x1440@144',availableModes:['2560x1440@144','1920x1080@60'],x:1920,y:0,scale:1.25,transform:0,enabled:true,mirror:''};
                page.monitors=[a,b]; page.draft=[a,b]; page.selectedName=b.name;
                page.arrange('mirror'); check(page.draft[1].mirror==='eDP-1','Mirror preset failed');
                page.arrange('internal'); check(!page.draft[1].enabled,'Internal preset failed');
                page.arrange('external'); check(!page.draft[0].enabled && page.draft[1].enabled,'External preset failed');
                page.arrange('extend'); check(page.draft[1].x===1920,'Extend preset failed');
                const rotation=find(page,'rotationChoice'); rotation.currentIndex=1; rotation.activated(1);
                check(page.selected.transform===1,'Rotation activation failed');
                rotation.currentIndex=0; rotation.activated(0);
                const resolution=find(page,'resolutionChoice'); resolution.currentIndex=1; resolution.activated(1);
                check(page.selected.mode==='1920x1080@60','Resolution activation failed');
                resolution.currentIndex=0; resolution.activated(0);
                const x=find(page,'xPositionChoice'); x.editText='-120'; x.accepted();
                check(page.selected.x===-120,'Editable themed coordinate failed');
                page.align('right'); check(page.selected.x===1920,'Align failed');
                page.transaction={phase:'idle'};
                capture.start();
            } catch(e) { console.error('DISPLAY_UI_FAIL '+e); Qt.quit(); }
        }
    }
    Timer {
        id: capture
        interval: 250
        onTriggered: {
            page.grabToImage(result => {
                result.saveToFile('/tmp/atomshell-display-check-'+root.stage+'.png');
                root.stage++;
                if(root.stage===1) {
                    page.flickable.contentY=Math.max(0,page.flickable.contentHeight+page.flickable.bottomMargin-page.flickable.height);
                } else if(root.stage===2) {
                    root.find(page,'xPositionChoice').popup.open();
                } else if(root.stage===3) {
                    root.find(page,'xPositionChoice').popup.close();
                    page.transaction={phase:'pending',deadline:Date.now()/1000+15};
                    page.flickable.contentY=0;
                    const before=page.selected.x; page.edit({x:99});
                    root.check(page.selected.x===before,'Pending preview allowed edits');
                } else { console.log('DISPLAY_UI_PASS'); Qt.quit(); return; }
                capture.restart();
            });
        }
    }
}'''
    fd, filename = tempfile.mkstemp(prefix='DisplayCheck',suffix='.qml',dir=shell)
    try:
        with os.fdopen(fd,'w') as stream: stream.write(qml)
        try:
            result=subprocess.run(['qs','--no-color','-p',filename],capture_output=True,text=True,timeout=15)
        except subprocess.TimeoutExpired as error:
            print((error.stdout or b'').decode(errors='replace')+(error.stderr or b'').decode(errors='replace'))
            raise
        output=result.stdout+result.stderr
        print(output)
        assert result.returncode==0 and 'DISPLAY_UI_PASS' in output
        assert not any(word in output for word in ('DISPLAY_UI_FAIL','TypeError','ReferenceError','Unable to assign','Cannot assign','is not a type'))
    finally:
        Path(filename).unlink(missing_ok=True)
