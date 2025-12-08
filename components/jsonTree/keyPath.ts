const utf8ToBase64 = (str: string) =>
  btoa(String.fromCharCode(...new TextEncoder().encode(str)));
const base64ToUtf8 = (b64: string) =>
  new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));

export const pathToPathStr = (path: string[]) => {
  return utf8ToBase64(JSON.stringify(path));
};

export const pathStrToPath = (pathStr: string) => {
  if (!pathStr) return [];
  return JSON.parse(base64ToUtf8(pathStr));
};
