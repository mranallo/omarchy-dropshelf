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
assert(context.localUrls(["file:///tmp/a", "https://example.test/b"]).length === 1, "localUrls rejects remote URLs");
assert(context.isImage("photo.WEBP"), "isImage recognizes supported extensions");
assert(!context.isImage("notes.txt"), "isImage rejects non-images");
assert(JSON.parse(context.serialize(added)).version === 1, "serialize emits versioned state");

console.log("model tests passed");
