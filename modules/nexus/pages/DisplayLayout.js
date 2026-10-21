.pragma library

function modeParts(mode) {
    const p = mode.replace(/Hz$/, "").split(/[x@]/).map(Number);
    return { width: p[0], height: p[1], hz: p[2] };
}

function fromMonitor(m) {
    const modes = (m.availableModes || []).map(v => v.replace(/Hz$/, ""));
    const matching = modes.find(v => {
        const p = modeParts(v);
        return Math.abs(p.hz - m.refreshRate) < 0.06 &&
            ((p.width === m.width && p.height === m.height) ||
             (m.transform % 2 && p.width === m.height && p.height === m.width));
    });
    return { name: m.name, description: m.description || m.name, focused: !!m.focused,
        mode: matching || modes[0] || `${m.width || 1920}x${m.height || 1080}@${Number(m.refreshRate || 60).toFixed(3)}`,
        availableModes: modes, x: m.x || 0, y: m.y || 0, scale: m.scale || 1,
        transform: m.transform || 0, enabled: !m.disabled,
        mirror: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "" };
}

function geometry(m) {
    const p = modeParts(m.mode);
    return { width: (m.transform % 2 ? p.height : p.width) / m.scale,
        height: (m.transform % 2 ? p.width : p.height) / m.scale };
}

function payload(items) {
    return items.map(m => ({ name: m.name, mode: m.mode, x: m.x, y: m.y,
        scale: m.scale, transform: m.transform, enabled: m.enabled, mirror: m.mirror }));
}

function bounds(items) {
    const active = items.filter(m => m.enabled && !m.mirror);
    if (!active.length) return { x: 0, y: 0, width: 1920, height: 1080 };
    const x = Math.min(...active.map(m => m.x)), y = Math.min(...active.map(m => m.y));
    return { x, y, width: Math.max(...active.map(m => m.x + geometry(m).width)) - x,
        height: Math.max(...active.map(m => m.y + geometry(m).height)) - y };
}

function preset(items, kind) {
    const result = JSON.parse(JSON.stringify(items));
    const internal = result.find(m => /^(eDP|LVDS|DSI)/i.test(m.name));
    const source = internal || result[0];
    let x = 0;
    for (const m of result) {
        m.enabled = kind === "internal" ? m === internal : kind === "external" ? m !== internal : true;
        m.mirror = kind === "mirror" && m !== source ? source.name : "";
        m.x = kind === "mirror" ? 0 : Math.round(x);
        m.y = 0;
        if (m.enabled && !m.mirror) x += geometry(m).width;
    }
    return result;
}

function snap(items, name, x, y) {
    const selected = items.find(m => m.name === name), size = geometry(selected);
    const peers = items.filter(m => m.name !== name && m.enabled && !m.mirror);
    let sx = Math.round(x), sy = Math.round(y), dx = 40, dy = 40;
    for (const m of peers) {
        const g = geometry(m);
        for (const value of [m.x, m.x + g.width, m.x - size.width, m.x + g.width - size.width]) {
            if (Math.abs(value - x) < dx) { dx = Math.abs(value - x); sx = Math.round(value); }
        }
        for (const value of [m.y, m.y + g.height, m.y - size.height, m.y + g.height - size.height]) {
            if (Math.abs(value - y) < dy) { dy = Math.abs(value - y); sy = Math.round(value); }
        }
    }
    return { x: sx, y: sy };
}
