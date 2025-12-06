const equals = (a: (string | number)[], b: (string | number)[]) => {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
};
const isTimestamp = (o: any, path: (string | number)[] = []) => {
  const timestampPath = [
    ["agent", "loggedInTime"],
    ["config", "preference", "lastStatusChangedTime"],
    ["config", "preference", "loginTime"],
    ["visitor", "lastGetSegmentChangedTime"],
    ["visitor", "lastGetNewVisitorTime"],
  ];
  for (const p of timestampPath) {
    if (equals(path, p)) {
      return typeof o === "number";
    }
  }
  return false;
};

export function tryParseNestedJson(
  o: any,
  path: (string | number)[] = [],
): any {
  if (isTimestamp(o, path)) {
    return new Date(o).toString();
  }

  if (typeof o === "string") {
    if (
      o.startsWith(
        "eyJhbGciOiJodHRwOi8vd3d3LnczLm9yZy8yMDAxLzA0L3htbGRzaWctbW9yZSNyc2Etc2hhMjU2IiwidHlwIjoiSldUIn0",
      )
    ) {
      return tryParseNestedJson(parseToken(o), path);
    }
    if (/^\/Date\((\d+)\)\/$/.test(o)) {
      return new Date(parseInt(o.match(/\/Date\((\d+)\)\//)![1])).toString();
    }

    try {
      return tryParseNestedJson(JSON.parse(o), path);
    } catch (e) {
      return o;
    }
  } else if (Array.isArray(o)) {
    return o.map((value, index) => tryParseNestedJson(value, [...path, index]));
  } else if (typeof o === "object" && o !== null) {
    const result: any = {};
    for (const key of Object.keys(o)) {
      result[key] = tryParseNestedJson(o[key], [...path, key]);
    }
    return result;
  } else {
    return o;
  }
}

function parseToken(o: string) {
  const token = JSON.parse(window.atob(o.split(".")[1]));
  if (token.exp) token.exp = new Date(token.exp * 1000).toString();
  if (token.nbf) token.nbf = new Date(token.nbf * 1000).toString();
  return token;
}
