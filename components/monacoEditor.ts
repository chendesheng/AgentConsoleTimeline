import loader from "@monaco-editor/loader";
import { html, css, LitElement, PropertyValues, PropertyValueMap } from "lit";
import { createRef, ref } from "lit/directives/ref.js";
import { customElement, property, query } from "lit/decorators.js";

declare var process: {
  env: {
    NODE_ENV: string;
  };
};

if (process.env.NODE_ENV === "production") {
  loader.config({ paths: { vs: "./vs" } });
}

@customElement("monaco-editor")
export class CodeEditor extends LitElement {
  @property()
  content = "";
  @property()
  language = "json";

  private readonly containerRef = createRef<HTMLDivElement>();

  editor!: any;
  monaco!: any;

  static styles = css`
    .container {
      height: 100%;
    }
  `;

  render() {
    return html`<div class="container" ${ref(this.containerRef)}></div>`;
  }

  protected firstUpdated(_changedProperties: PropertyValues): void {
    loader.init().then((monaco) => {
      this.monaco = monaco;

      // Copy over editor styles
      const styles = document.querySelectorAll(
        "link[rel='stylesheet'][data-name^='vs/']"
      );
      for (const style of styles) {
        this.renderRoot.appendChild(style.cloneNode(true));
      }

      this.editor = this.monaco.editor.create(this.containerRef.value!, {
        language: this.language,
        automaticLayout: true,
        theme: "vs-dark",
        value: formatJson(this.content),
        readOnly: true,
        wordWrap: "on"
      });
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

  private readonly containerRef = createRef<HTMLDivElement>();

  editor: any;
  monaco: any;

  static styles = css`
    .container {
      height: 100%;
    }
  `;

  render() {
    return html`<div class="container" ${ref(this.containerRef)}></div>`;
  }

  protected firstUpdated(_changedProperties: PropertyValues): void {
    loader.init().then((monaco) => {
      this.monaco = monaco;

      // Copy over editor styles
      const styles = document.querySelectorAll(
        "link[rel='stylesheet'][data-name^='vs/']"
      );
      for (const style of styles) {
        this.renderRoot.appendChild(style.cloneNode(true));
      }

      this.editor = this.monaco.editor.createDiffEditor(
        this.containerRef.value!,
        {
          language: this.language,
          originalEditable: false,
          automaticLayout: true,
          theme: "vs-dark",
          readOnly: true,
          wordWrap: "on",
          diffWordWrap: true
        }
      );

      this.setModels();
    });
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
      )
    });
  }

  protected updated(changedProperties: PropertyValues): void {
    if (
      (changedProperties.has("original") || changedProperties.has("modified")) &&
      this.editor
    ) {
      this.setModels();
    }
  }
}

function formatJson(s: string) {
  return JSON.stringify(JSON.parse(s), null, 4);
}
