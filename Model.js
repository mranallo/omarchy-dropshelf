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
