#!/usr/bin/env python3
"""Run: python3 ~/.config/quickshell/caelestia/utils/check_shortcuts.py"""
import json
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch
import builtin_shortcuts as backend

SHELL = Path(__file__).resolve().parent.parent
for value in ('SUPER + T', 'CTRL + SUPER + Page_Down', 'SUPER + ALT + P', 'SUPER + mouse:272'):
    assert backend.canonical(backend.validate(value)) == backend.canonical(value)
for value in ('', 'SUPER +', 'SUPER + SUPER + T', 'SUPER + not_a_real_key', 'SUPER + T\nreturn {}', 'SUPER + "T"', 'SUPER + $(touch x)'):
    try:
        backend.validate(value)
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid key accepted: ' + repr(value))
assert backend.canonical('ALT + SUPER + T') == backend.canonical('super + alt + t')

with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    reloads = []
    fail = [False]
    def registry():
        path = directory / 'keybind-overrides.json'
        state = json.loads(path.read_text()) if path.exists() else {}
        return [{'original': key, 'key': state.get(backend.canonical(key), key)} for key in ('SUPER + T', 'SUPER + Y')]
    def run(*args):
        if args[0] == 'luac':
            return subprocess.check_output(args, text=True)
        if args == ('hyprctl', '-j', 'binds'):
            return '[]'
        if args == ('hyprctl', 'reload'):
            reloads.append(True)
        if args == ('hyprctl', 'configerrors') and fail[0]:
            return 'simulated config error'
        return ''
    with patch.object(backend, 'DIRECTORY', directory), patch.object(backend, 'registry', registry), patch.object(backend, 'run', run):
        backend.update('SUPER + T', 'CTRL + SUPER + F12')
        assert registry()[0]['key'] == 'CTRL + SUPER + F12'
        old = {p.name: p.read_bytes() for p in directory.iterdir()}
        try:
            backend.update('SUPER + T', 'SUPER + Y')
        except ValueError as error:
            assert 'already used' in str(error)
        else:
            raise AssertionError('Conflict accepted')
        assert old == {p.name: p.read_bytes() for p in directory.iterdir()}
        fail[0] = True
        try:
            backend.update('SUPER + T', 'CTRL + SUPER + F11')
        except ValueError:
            pass
        else:
            raise AssertionError('Invalid reload accepted')
        assert old == {p.name: p.read_bytes() for p in directory.iterdir()}, 'Rollback lost previous settings'
        fail[0] = False
        backend.update('SUPER + T', '', reset=True)
        assert registry()[0]['key'] == 'SUPER + T'

lua = '''
local native_loadfile = loadfile
loadfile = function(path)
    if path:match("keybind%-overrides.lua$") then return function() return {["super+t"]="CTRL + SUPER + Y"} end end
    return native_loadfile(path)
end
local action = function() return 42 end
local opts = {release=true, repeating=true}
local seen
hl = {bind=function(keys, callback, flags) seen={keys, callback, flags}; return seen end,
      unbind=function(keys) seen=keys end}
local original = hl.bind
local editor = dofile(arg[1])
editor.start()
local handle = hl.bind("SUPER + T", action, opts)
assert(handle[1]=="CTRL + SUPER + Y" and handle[2]==action and handle[3]==opts)
assert(handle[2]()==42 and handle[3].release and handle[3].repeating)
assert(nexusKeybinds["super+t"].original=="SUPER + T")
hl.unbind("SUPER + T")
assert(seen=="CTRL + SUPER + Y" and nexusKeybinds["super+t"]==nil)
editor.finish()
assert(hl.bind==original)
'''
subprocess.run(['lua', '-', str(Path.home()/'.config/caelestia/keybind-editor.lua')], input=lua, text=True, check=True)

javascript = r'''
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const root = process.argv[1], context = {qsTr: text => text};
vm.createContext(context);
vm.runInContext(fs.readFileSync(root + '/utils/ShortcutSearch.js', 'utf8'), context);
const groups = context.catalog();
const keys = (query, category='') => Array.from(context.filterGroups(groups, query, category).flatMap(group => group.entries.map(entry => entry[0])));
assert.deepStrictEqual(keys('Win+T'), ['Super + T']);
assert.deepStrictEqual(keys('Super+Alt+Space'), ['Super + Alt + Space']);
assert.deepStrictEqual(keys('pencereyi küçült'), ['Super + Alt + arrows']);
assert.deepStrictEqual(keys('PENCEREYİ KÜÇÜLT'), keys('pencereyi kucult'));
assert.deepStrictEqual(keys('Spotify'), ['Super + M']);
assert.deepStrictEqual(keys('tüm pencereleri göster'), ['Super + Tab']);
assert.deepStrictEqual(keys('ekranı ikiye böl'), ['Tiling vs floating', 'Super + Alt + Space']);
assert(keys('pencereyi başka masaüstüne taşımak istiyorum').includes('Super + Alt + 0–9'));
assert(!keys('pencereyi başka masaüstüne taşımak istiyorum').includes('Super + 0–9'));
assert.deepStrictEqual(keys('sesini kis'), ['XF86 Volume Up / Down']);
assert(keys('"tam ekran"').includes('Super + F'));
assert(keys('ekran goruntusu almak istiyorum').includes('Super + Shift + S'));
assert.deepStrictEqual(keys('sekmeleri birlestir'), ['Super + B']);
assert.deepStrictEqual(keys('xyzzynothingmatches'), []);
assert(keys('', 'windows').length === 16);
const custom = [{id: 'custom', title:'Custom', entries:[['SUPER + Y', 'Deneme', ['echo test']]]}];
assert(context.filterGroups(custom, 'echo test', '').length === 1);
assert(context.filterGroups(custom, 'Deneme', 'windows').length === 0);
const bindings = [{original:'SUPER + T', key:'SUPER + Y', changed:true}];
const group = groups.find(group => group.id === 'apps');
assert(context.withBindings(group, bindings).entries.find(entry => entry[1] === 'Terminal')[0] === 'SUPER + Y');
assert(context.bindingCandidates(['Super + Alt + arrows'], [{original:'ALT + SUPER + right'}]).length === 1);
assert(context.bindingCandidates(['Super + wheel'], [{original:'SUPER + mouse_down'}]).length === 1);
assert(context.bindingCandidates(['Super + Page Up / Down'], [{original:'SUPER + Page_Down'}]).length === 1);
assert(context.bindingCandidates(['Super + 0–9'], [{original:'SUPER + 0'}]).length === 1);
assert(context.bindingCandidates(['F10 · Konuşmadan yazıya'], [{original:'XF86PickupPhone'}]).length === 1);
assert.deepStrictEqual(keys('f11'), ['F11 · Ekrandan yazı kopyala']);
assert.deepStrictEqual(keys('f12').sort(), ['Super + Alt + F12', 'F12 · Yıldız'].sort());
const launcher = fs.readFileSync(root + '/modules/launcher/AppList.qml', 'utf8');
let opened;
Object.assign(context, {ShortcutSearch: context, shortcutGroups: groups, GlobalConfig: {launcher: {actionPrefix: '>'}},
    PageRegistry: {shortcutsPageIndex: 8}, WindowFactory: {create: (_, props) => opened = props}});
for (const name of ['stateForText', 'shortcutResults']) {
    const body = launcher.match(new RegExp('function ' + name + '\\(text: string\\): \\w+ \\{([\\s\\S]*?)\\n    \\}'))[1];
    vm.runInContext('function ' + name + '(text) {' + body + '\n}', context);
}
assert.strictEqual(context.stateForText('>shortcuts'), 'shortcuts');
assert.strictEqual(context.stateForText('>shortcuts pencere'), 'shortcuts');
assert.strictEqual(context.stateForText('>shortcutsXYZ'), 'actions');
assert.strictEqual(context.stateForText('terminal'), 'apps');
const results = context.shortcutResults('>shortcuts pencereyi küçült');
assert.strictEqual(results.length, 1);
assert.strictEqual(results[0].name, 'Super + Alt + arrows');
const state = {launcher: true};
results[0].onClicked({screenState: state});
assert(!state.launcher && opened.initialPage === 8 && opened.initialShortcutQuery === 'pencereyi küçült');
'''
subprocess.run(['node', '-e', javascript, str(SHELL)], check=True)
print('PASS: validation, conflicts, save/reset, rollback, actions/flags, Turkish search, aliases, categories, custom shortcuts, launcher routing/results/navigation')
