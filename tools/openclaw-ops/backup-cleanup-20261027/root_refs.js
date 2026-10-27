// Metadata only: no cmdline, environ, credentials, databases or host file contents.
const fs = require('node:fs');
const approved = JSON.parse(fs.readFileSync('/targets.json', 'utf8')).paths;
const targets = approved.flatMap(t => [t, t + '.cleanup-20261027-pending']);
let matches = 0, permissionDenials = 0, processes = 0, mountMatches = 0;
const namespaces = new Set();
const denied = e => {
  if (['EACCES', 'EPERM'].includes(e.code)) permissionDenials++;
  else if (!['ENOENT', 'ESRCH', 'EINVAL'].includes(e.code)) throw e;
};
const match = value => {
  if (targets.some(t => value === t || value.startsWith(t + '/'))) matches++;
};
const within = (value, parent) => value === parent || value.startsWith(parent.replace(/\/$/, '') + '/');
const decode = value => value.replace(/\\([0-7]{3})/g,
  (_, octal) => String.fromCharCode(parseInt(octal, 8)));
const mounts = text => text.trim().split('\n').filter(Boolean).map(line => {
  const fields = line.split(' ');
  return {device: fields[2], root: decode(fields[3]), point: decode(fields[4])};
});
// PID1 describes the host mapping. Translate paths into filesystem coordinates
// so a bind alias outside the target is caught in any observed mount namespace.
const hostMounts = mounts(fs.readFileSync('/proc/1/mountinfo', 'utf8'));
const backing = targets.map(target => {
  const host = hostMounts.filter(m => within(target, m.point))
    .sort((a, b) => b.point.length - a.point.length)[0];
  if (!host) throw new Error('host target filesystem mapping unavailable');
  const suffix = target.slice(host.point === '/' ? 0 : host.point.length);
  return {target, device: host.device, fsPath: (host.root.replace(/\/$/, '') + suffix) || '/'};
});
for (const pid of fs.readdirSync('/proc').filter(x => /^\d+$/.test(x))) {
  processes++;
  try {
    const ns = fs.readlinkSync('/proc/' + pid + '/ns/mnt');
    if (!namespaces.has(ns)) {
      const mountinfo = fs.readFileSync('/proc/' + pid + '/mountinfo', 'utf8');
      for (const mount of mounts(mountinfo)) {
        if (targets.some(t => within(mount.point, t))) mountMatches++;
        for (const item of backing) {
          if (mount.device !== item.device) continue;
          if (within(mount.root, item.fsPath)) {
            mountMatches++;
          } else if (within(item.fsPath, mount.root)) {
            const suffix = item.fsPath.slice(mount.root === '/' ? 0 : mount.root.length);
            const alias = (mount.point.replace(/\/$/, '') + suffix) || '/';
            if (alias !== item.target) mountMatches++;
          }
        }
      }
      namespaces.add(ns);
    }
  } catch(e) { denied(e); }
  try {
    for (const line of fs.readFileSync('/proc/' + pid + '/maps', 'utf8').split('\n')) {
      const path = line.trim().split(/\s+/).slice(5).join(' ');
      match(path);
    }
  } catch(e) { denied(e); }
  const links = ['cwd', 'exe', 'root'];
  try { links.push(...fs.readdirSync('/proc/' + pid + '/fd').map(n => 'fd/' + n)); }
  catch(e) { denied(e); }
  for (const link of links) {
    try { match(fs.readlinkSync('/proc/' + pid + '/' + link)); }
    catch(e) { denied(e); }
  }
}
console.log(JSON.stringify({matches, mountMatches, permissionDenials, processes,
  mountNamespaces: namespaces.size, epoch: Date.now()/1000}));
process.exit(matches === 0 && mountMatches === 0 && permissionDenials === 0 ? 0 : 1);

