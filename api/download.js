// Sends a file built in the dashboard back to the browser as a real download with its name.
// Safari on this site ignores the file name on blob:/data: links ("Safari Can't Open the Page"),
// so the dashboard posts the file here. Nothing is stored: the file is only echoed back.
const TYPES = {
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  json: 'application/json', csv: 'text/csv', pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg'
};
module.exports = (req, res) => {
  if (req.method !== 'POST') { res.statusCode = 405; res.end('POST only'); return; }
  const body = req.body || {};
  let name = String(body.name || 'download.xlsx').replace(/[\r\n"\\/:*?<>|]+/g, ' ').trim().slice(0, 150);
  const ext = (name.match(/\.([a-z0-9]+)$/i) || [])[1];
  if (!ext || !TYPES[ext.toLowerCase()]) name += '.xlsx';
  const type = TYPES[(name.match(/\.([a-z0-9]+)$/i) || [])[1].toLowerCase()];
  const data = String(body.data || '');
  if (!data || data.length > 4.3 * 1024 * 1024) { res.statusCode = 400; res.end('Bad file'); return; }
  const buf = Buffer.from(data, 'base64');
  const ascii = name.replace(/[^\x20-\x7e]/g, '_');
  res.setHeader('Content-Type', type);
  res.setHeader('Content-Disposition', `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.end(buf);
};
