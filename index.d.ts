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

declare module "*?worker" {
  const workerConstructor: {
    new (): Worker;
  };
  export default workerConstructor;
}
