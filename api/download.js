// Sends an Excel file built in the dashboard back to the browser as a real download with its name.
// Safari on this site ignores the file name on blob:/data: links, so the dashboard posts the file here.
// Nothing is stored: the file is only echoed back.
module.exports = (req, res) => {
  if (req.method !== 'POST') { res.statusCode = 405; res.end('POST only'); return; }
  const body = req.body || {};
  let name = String(body.name || 'download.xlsx').replace(/[\r\n"\\/:*?<>|]+/g, ' ').trim().slice(0, 150);
  if (!/\.xlsx$/i.test(name)) name += '.xlsx';
  const data = String(body.data || '');
  if (!data || data.length > 4 * 1024 * 1024) { res.statusCode = 400; res.end('Bad file'); return; }
  const buf = Buffer.from(data, 'base64');
  if (buf.length < 4 || buf[0] !== 0x50 || buf[1] !== 0x4b) { res.statusCode = 400; res.end('Not an Excel file'); return; }
  const ascii = name.replace(/[^\x20-\x7e]/g, '_');
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.end(buf);
};
