const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync("Model.js", "utf8").replace(/^\.pragma library\s*/m, "");
const context = {};
vm.createContext(context);
vm.runInContext(source, context);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const parsed = context.parseState('{"items":[{"uri":"file:///tmp/one%20file.png"},{"uri":"https://example.test/no"}]}');
assert(parsed.length === 1, "parseState keeps local files only");
assert(parsed[0].name === "one file.png", "displayName decodes URI components");

const added = context.addUrls(parsed, ["file:///tmp/one%20file.png", "file:///tmp/two.txt"]);
assert(added.length === 2, "addUrls de-duplicates entries");
assert(context.removeAt(added, 0)[0].name === "two.txt", "removeAt removes the selected entry");
assert(context.removeUri(added, "file:///tmp/two.txt").length === 1, "removeUri removes the dragged entry by stable URI");
assert(context.localUrls(["file:///tmp/a", "https://example.test/b"]).length === 1, "localUrls rejects remote URLs");
assert(context.remoteImageUrl(["https://example.test/photo.png"], "", "") === "https://example.test/photo.png", "remoteImageUrl reads URI drops");
assert(context.remoteImageUrl([], "", '<img src="https://example.test/photo.webp">') === "https://example.test/photo.webp", "remoteImageUrl reads browser HTML drops");
assert(context.remoteImageUrl([], "", "", "https://example.test/native.gif\n") === "https://example.test/native.gif", "remoteImageUrl reads native browser URL formats");
assert(context.remoteImageUrl(["https://www.google.com/imgres?imgurl=https%3A%2F%2Fexample.test%2Ffull.jpg&imgrefurl=https%3A%2F%2Fexample.test"], "", "") === "https://example.test/full.jpg", "remoteImageUrl extracts Google image result URLs");
assert(context.remoteImageUrl([], "https://www.google.com/url?mediaurl=https%253A%252F%252Fexample.test%252Fphoto.png&x=1", "") === "https://example.test/photo.png", "remoteImageUrl extracts encoded Google media URLs");
assert(context.remoteImageUrl([], "https://www.google.com/imgres?imgurl=https%3A%2F%2Fexample.test%2Fphoto.webp&amp;imgrefurl=x", "") === "https://example.test/photo.webp", "remoteImageUrl handles HTML-escaped Google result URLs");
assert(context.remoteImageUrl([], "Image\nimgurl=https%253A%252F%252Fexample.test%252Fnested.jpg&other=1", "") === "https://example.test/nested.jpg", "remoteImageUrl handles embedded Google parameters");
assert(context.remoteImageUrl([], "not a URL", "") === "", "remoteImageUrl rejects arbitrary text");

const giphyGrid = context.remoteImageCandidates(
  ["https://giphy.com/gifs/rihanna-makeout-bGPTxLislwm3u"],
  "https://giphy.com/gifs/rihanna-makeout-bGPTxLislwm3u",
  '<img class="giphy-gif-img" src="https://media0.giphy.com/media/bGPTxLislwm3u/giphy.gif">',
  "");
assert(giphyGrid[0] === "https://media0.giphy.com/media/bGPTxLislwm3u/giphy.gif", "giphy grid ranks the HTML image over the page URL");
assert(giphyGrid[giphyGrid.length - 1] === "https://giphy.com/gifs/rihanna-makeout-bGPTxLislwm3u", "giphy page URL stays as last resort");
assert(giphyGrid.length === 2, "candidates are deduplicated");

const googleGrid = context.remoteImageCandidates(
  ["https://www.google.com/search?q=cats&udm=2"],
  "",
  '<img src="data:image/jpeg;base64,/9j/4AAQSkZJRg==" alt="cat">',
  "");
assert(googleGrid[0] === "data:image/jpeg;base64,/9j/4AAQSkZJRg==", "google grid ranks the data URI over the search page");

const googleExpanded = context.remoteImageCandidates(
  ["https://www.google.com/imgres?imgurl=https%3A%2F%2Fexample.test%2Fphoto%2520name.jpg&imgrefurl=https%3A%2F%2Fexample.test%2Fpage"],
  "", "", "");
assert(googleExpanded[0] === "https://example.test/photo%20name.jpg", "single-encoded imgurl is decoded exactly once");

const promiseWithPage = context.remoteImageCandidates(
  [], "", "", "https://www.google.com/imgres?imgurl=https%3A%2F%2Fexample.test%2Ffull.jpg&imgrefurl=x\nTitle");
assert(promiseWithPage[0] === "https://example.test/full.jpg", "extraction outranks a native page URL");

const parsedData = context.parseDataUri("data:image/png;base64,iVBORw0KGgo=");
assert(parsedData && parsedData.mime === "image/png" && parsedData.base64 === "iVBORw0KGgo=", "parseDataUri parses base64 image URIs");
assert(context.parseDataUri("data:text/html;base64,PGI+") === null, "parseDataUri rejects non-images");
assert(context.parseDataUri("data:image/png,rawpixels") === null, "parseDataUri rejects non-base64 payloads");

assert(context.refererFor("https://media0.giphy.com/media/x/g.gif") === "https://media0.giphy.com/", "refererFor derives the URL origin");
assert(context.looksLikeImageUrl("https://example.test/pic.JPG?w=200"), "looksLikeImageUrl accepts image extensions with queries");
assert(context.looksLikeImageUrl("https://encrypted-tbn0.gstatic.com/images?q=tbn:abc"), "looksLikeImageUrl accepts gstatic thumbnails");
assert(!context.looksLikeImageUrl("https://example.test/articles/cats"), "looksLikeImageUrl rejects plain page URLs");

function bufferOf(text) {
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i);
  return bytes.buffer;
}
assert(context.base64FromArrayBuffer(bufferOf("Man")) === "TWFu", "base64FromArrayBuffer encodes full triples");
assert(context.base64FromArrayBuffer(bufferOf("Ma")) === "TWE=", "base64FromArrayBuffer pads two-byte tails");
assert(context.base64FromArrayBuffer(bufferOf("M")) === "TQ==", "base64FromArrayBuffer pads one-byte tails");
assert(context.base64FromArrayBuffer(new ArrayBuffer(0)) === "", "base64FromArrayBuffer handles empty buffers");
const longBuffer = bufferOf("light work.".repeat(1000));
assert(context.base64FromArrayBuffer(longBuffer) === Buffer.from("light work.".repeat(1000)).toString("base64"), "base64FromArrayBuffer matches Node across chunk boundaries");
assert(context.isImage("photo.WEBP"), "isImage recognizes supported extensions");
assert(!context.isImage("notes.txt"), "isImage rejects non-images");
assert(JSON.parse(context.serialize(added)).version === 1, "serialize emits versioned state");

console.log("model tests passed");
