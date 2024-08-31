import loader from "@monaco-editor/loader";
import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, query } from "lit/decorators.js";
import { sort as sortKeys } from "json-keys-sort";

declare var process: {
  env: {
    NODE_ENV: string;
  };
};

if (process.env.NODE_ENV === "production") {
  loader.config({ paths: { vs: "./vs" } });
}

const loaderPromise = loader.init();

@customElement("monaco-editor")
export class CodeEditor extends LitElement {
  @property()
  content = "";
  @property()
  language = "json";

  @query(".container")
  container!: HTMLDivElement;

  editor!: any;
  monaco!: any;

  static styles = css`
    .container {
      height: 100%;
      display: none;
    }
    .container.loaded {
      display: block;
    }
  `;

  render() {
    return html`<div class="container"></div>`;
  }

  protected async firstUpdated(_changedProperties: PropertyValues) {
    this.monaco = await loaderPromise;
    this.monaco.editor.onDidCreateEditor((editor: any) => {
      const addLoadedClass = () => {
        if (!this.container.classList.contains("loaded")) {
          this.container.classList.add("loaded");
        }
      };
      cloneStyles(this.renderRoot, addLoadedClass);
    });

    this.editor = this.monaco.editor.create(this.container, {
      language: this.language,
      automaticLayout: true,
      theme: "vs-dark",
      value: formatJson(this.content),
      readOnly: true,
      wordWrap: "on",
    });
  }

  protected updated(changedProperties: PropertyValues): void {
    if (changedProperties.has("content") && this.editor) {
      this.editor.setValue(formatJson(this.content));
    }
  }
}

@customElement("monaco-diff-editor")
export class MonacoDiffEditor extends LitElement {
  @property()
  language = "json";
  @property()
  original: string = "";
  @property()
  modified: string = "";

  @query(".container")
  container!: HTMLDivElement;

  editor: any;
  monaco: any;

  static styles = css`
    .container {
      height: 100%;
      display: none;
    }
    .container.loaded {
      display: block;
    }
  `;

  render() {
    return html`<div class="container"></div>`;
  }

  protected async firstUpdated(_changedProperties: PropertyValues) {
    this.monaco = await loaderPromise;
    this.monaco.editor.onDidCreateDiffEditor((editor: any) => {
      const addLoadedClass = () => {
        if (!this.container.classList.contains("loaded")) {
          this.container.classList.add("loaded");
        }
      };
      cloneStyles(this.renderRoot, addLoadedClass);
    });

    this.editor = this.monaco.editor.createDiffEditor(this.container, {
      language: this.language,
      originalEditable: false,
      automaticLayout: true,
      theme: "vs-dark",
      readOnly: true,
      wordWrap: "on",
      diffWordWrap: true,
    });

    this.setModels();
  }

  private setModels() {
    if (!this.editor) return;
    if (!this.monaco) return;

    this.editor.setModel({
      original: this.monaco.editor.createModel(
        formatJson(this.original),
        this.language
      ),
      modified: this.monaco.editor.createModel(
        formatJson(this.modified),
        this.language
      ),
    });
  }

  protected updated(changedProperties: PropertyValues): void {
    if (
      (changedProperties.has("original") ||
        changedProperties.has("modified")) &&
      this.editor
    ) {
      this.setModels();
    }
  }
}

function formatJson(s: string) {
  return JSON.stringify(sortKeys(JSON.parse(s)), null, 4);
}

function cloneStyles(root: HTMLElement | DocumentFragment, onload: () => void) {
  // Copy over editor styles
  const styles = document.querySelectorAll(
    "link[rel='stylesheet'][data-name^='vs/']"
  );
  for (const style of styles) {
    const cloned = style.cloneNode(true) as HTMLLinkElement;
    cloned.onload = onload;
    root.prepend(cloned);
  }
}
