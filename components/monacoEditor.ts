import * as monaco from "monaco-editor";
import { LitElement, PropertyValues } from "lit";
import { customElement, property } from "lit/decorators.js";
import { sort as sortKeys } from "json-keys-sort";
import beautify from "js-beautify";

@customElement("monaco-editor")
export class CodeEditor extends LitElement {
  @property({ type: String })
  content = "";
  @property({ type: String })
  language = "json";
  @property({ type: Boolean })
  format: boolean = false;

  editor?: monaco.editor.IStandaloneCodeEditor;

  protected createRenderRoot(): HTMLElement | DocumentFragment {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();

    this.editor = monaco.editor.create(this, {
      language: this.language,
      automaticLayout: true,
      theme: "vs-dark",
      value: this.getContent(),
      readOnly: true,
      wordWrap: "on",
    });
  }

  protected updated(changedProperties: PropertyValues): void {
    if (
      (changedProperties.has("content") ||
        changedProperties.has("language") ||
        changedProperties.has("format")) &&
      this.editor
    ) {
      const model = monaco.editor.createModel(this.getContent(), this.language);
      this.editor.setModel(model);
    }
  }

  private getContent() {
    if (this.format) {
      if (this.language === "json") {
        return formatJson(this.content);
      } else if (this.language === "html") {
        return beautify.html(this.content);
      } else if (this.language === "xml") {
        return beautify.html(this.content);
      } else if (this.language === "css") {
        return beautify.css(this.content);
      } else if (this.language === "javascript") {
        return beautify.js(this.content);
      }
    }
    return this.content;
  }
}

@customElement("monaco-diff-editor")
export class MonacoDiffEditor extends LitElement {
  @property({ type: String })
  language = "json";
  @property({ type: String })
  original: string = "";
  @property({ type: String })
  modified: string = "";

  editor?: monaco.editor.IStandaloneDiffEditor;

  protected createRenderRoot(): HTMLElement | DocumentFragment {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();

    this.editor = monaco.editor.createDiffEditor(this, {
      originalEditable: false,
      automaticLayout: true,
      theme: "vs-dark",
      readOnly: true,
      wordWrap: "on",
      diffWordWrap: "on",
      hideUnchangedRegions: {
        enabled: true,
        contextLineCount: 10,
      },
    });
  }

  private setModels() {
    if (!this.editor) return;

    this.editor.setModel({
      original: monaco.editor.createModel(
        formatJson(this.original),
        this.language,
      ),
      modified: monaco.editor.createModel(
        formatJson(this.modified),
        this.language,
      ),
    });
  }

  protected updated(changedProperties: PropertyValues): void {
    if (
      changedProperties.has("original") ||
      changedProperties.has("modified")
    ) {
      this.setModels();
    }
  }
}

function formatJson(s: string) {
  try {
    return JSON.stringify(sortKeys(JSON.parse(s)), null, 4);
  } catch (e) {
    return s;
  }
}
