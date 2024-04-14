import { EditorView } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { json } from "@codemirror/lang-json";
import { html, css, LitElement, PropertyValues, PropertyValueMap } from "lit";
import { customElement, property, query } from "lit/decorators.js";
import theme from "./codeEditorTheme";
import { vim } from "@replit/codemirror-vim";
import { basicSetup } from "./codeEditorSetup";

@customElement("code-editor")
export class CodeEditor extends LitElement {
  @property()
  content = "";

  @query("#editor")
  container!: HTMLElement;

  editor: EditorView | null = null;

  render() {
    return html`<div id="editor"></div>`;
  }

  static styles = css`
    #editor {
      width: 100%;
      height: 100%;
    }
    .cm-editor {
      height: 100%;
    }
    .cm-lineNumbers {
      padding: 0 2px;
      min-width: 22px;

      color: hsl(0, 0%, 57%);

      font:
        8px/13px -webkit-system-font,
        Menlo,
        Monaco,
        monospace;
      font-variant-numeric: tabular-nums;
      text-align: right;
    }
    .cm-gutters {
      flex-flow: row-reverse;
      background-color: var(--background-color);
      border-right: solid 1px var(--text-color-quaternary);
    }
  `;

  protected firstUpdated(
    _changedProperties: PropertyValueMap<any> | Map<PropertyKey, unknown>,
  ): void {
    this.editor = new EditorView({
      parent: this.container,
      doc: formatJson(this.content),
      extensions: [
        vim(),
        basicSetup,
        json(),
        EditorView.lineWrapping,
        theme,
        EditorState.readOnly.of(true),
      ],
    });
  }

  private _setContent(value: string) {
    this.editor?.dispatch({
      changes: {
        from: 0,
        to: this.editor.state.doc.length,
        insert: value,
      },
    });
  }

  updated(changed: PropertyValues<this>) {
    if (changed.has("content")) {
      this._setContent(formatJson(this.content));
    }
  }
}

function formatJson(s: string) {
  return JSON.stringify(JSON.parse(s), null, 4);
}
