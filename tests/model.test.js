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
assert(context.remoteImageUrl([], "not a URL", "") === "", "remoteImageUrl rejects arbitrary text");
assert(context.isImage("photo.WEBP"), "isImage recognizes supported extensions");
assert(!context.isImage("notes.txt"), "isImage rejects non-images");
assert(JSON.parse(context.serialize(added)).version === 1, "serialize emits versioned state");

console.log("model tests passed");
