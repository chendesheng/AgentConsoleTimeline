declare module "*.elm" {
  export const Elm: {
    Main: {
      init: (options: { node: HTMLElement; flags: any }) => {
        ports: {
          [key: string]: {
            send: (_: any) => void;
            subscribe: (callback: (_: any) => void) => void;
          };
        };
      };
    };
  };
}

declare module "@alenaksu/json-viewer/JsonViewer.js" {
  export class JsonViewer extends HTMLElement {
    expandAll(): void;
    collapseAll(): void;
    resetFilter(): void;
    filter(regex: RegExp): void;
    requestUpdate(): void;
    static customRenderer(value: any, path: string): any;
    static styles: any;
  }
}

declare module "js-beautify" {
  export function html(html: string): string;
  export function css(css: string): string;
  export function js(js: string): string;
}

declare module "jsondiffpatch" {
  export function diff(a: any, b: any): any;
}

declare module "*.svg" {
  const content: string;
  export default content;
}

declare module "*?worker" {
  const workerConstructor: {
    new (): Worker;
  };
  export default workerConstructor;
}
declare module "*.css?inline" {
  const content: string;
  export default content;
}
