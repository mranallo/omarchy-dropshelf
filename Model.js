.pragma library

function parseState(text) {
  if (!text)
    return [];
  try {
    const parsed = JSON.parse(String(text));
    if (!parsed || !Array.isArray(parsed.items))
      return [];
    return parsed.items.filter(function(item) {
      return item && typeof item.uri === "string" && item.uri.startsWith("file://");
    }).map(function(item) {
      return { uri: item.uri, name: displayName(item.uri) };
    });
  } catch (error) {
    return [];
  }
}

function serialize(entries) {
  return JSON.stringify({
    version: 1,
    items: (entries || []).map(function(item) { return { uri: item.uri }; })
  }, null, 2) + "\n";
}

function localUrls(urls) {
  const result = [];
  for (let i = 0; i < urls.length; i++) {
    const uri = String(urls[i]);
    if (uri.startsWith("file://") && result.indexOf(uri) === -1)
      result.push(uri);
  }
  return result;
}

function remoteImageUrl(urls, text, html, nativeUrl) {
  const candidates = [];
  for (let i = 0; i < (urls || []).length; i++)
    candidates.push(String(urls[i]));
  if (text)
    candidates.push(String(text).trim());
  if (html) {
    const source = String(html);
    const match = source.match(/<img\b[^>]*\bsrc=["']([^"']+)["']/i);
    if (match) candidates.push(match[1]);
    const sourceSet = source.match(/<img\b[^>]*\bsrcset=["']([^"']+)["']/i);
    if (sourceSet) candidates.push(sourceSet[1].split(/[\s,]+/)[0]);
  }
  if (nativeUrl)
    candidates.push(String(nativeUrl).trim().split(/[\r\n]/)[0]);

  for (let j = 0; j < candidates.length; j++) {
    const candidate = extractGoogleImageUrl(candidates[j]);
    if (/^https?:\/\/[^\s]+$/i.test(candidate)) return candidate;
  }
  return "";
}

function extractGoogleImageUrl(value) {
  let candidate = String(value || "").trim()
    .replace(/&amp;/g, "&")
    .replace(/\\u003d/g, "=")
    .replace(/\\u0026/g, "&")
    .replace(/\\u002f/gi, "/");
  if (!candidate) return "";

  const googleParam = candidate.match(/(?:imgurl|mediaurl)(?:=|%3D)(https?(?:%25?3A|:)(?:%25?2F|\/){2}[^&\s"']+)/i);
  if (googleParam) {
    try { return decodeURIComponent(decodeURIComponent(googleParam[1])); }
    catch (error) { return googleParam[1]; }
  }

  const prefixed = candidate.match(/https?:\/\/[^\s\r\n"']+/i);
  if (prefixed) candidate = prefixed[0].replace(/[),.;]+$/, "");

  const lines = candidate.split(/[\r\n]+/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (/^https?:\/\//i.test(line)) {
      candidate = line;
      break;
    }
  }

  try {
    let decoded = candidate;
    for (let i = 0; i < 2; i++) decoded = decodeURIComponent(decoded);
    const match = decoded.match(/[?&](?:imgurl|mediaurl)=([^&]+)/i);
    if (match) return decodeURIComponent(match[1]);
  } catch (error) { }
  return candidate;
}

function addUrls(entries, urls) {
  const result = (entries || []).slice();
  const seen = {};
  for (let i = 0; i < result.length; i++)
    seen[result[i].uri] = true;
  for (let j = 0; j < urls.length; j++) {
    if (!seen[urls[j]]) {
      result.push({ uri: urls[j], name: displayName(urls[j]) });
      seen[urls[j]] = true;
    }
  }
  return result;
}

function removeAt(entries, index) {
  const result = (entries || []).slice();
  if (index >= 0 && index < result.length)
    result.splice(index, 1);
  return result;
}

function removeUri(entries, uri) {
  return (entries || []).filter(function(item) { return item.uri !== uri; });
}

function displayName(uri) {
  const parts = String(uri).split("/");
  const encoded = parts.length > 0 ? parts[parts.length - 1] : "File";
  try {
    return decodeURIComponent(encoded) || "File";
  } catch (error) {
    return encoded || "File";
  }
}

function isImage(name) {
  return /\.(avif|bmp|gif|heic|heif|jpe?g|png|svg|webp)$/i.test(String(name));
}
