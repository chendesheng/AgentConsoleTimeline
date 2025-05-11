import { css, html, LitElement, PropertyValues, unsafeCSS } from "lit";
import { customElement, property, query } from "lit/decorators.js";
import hexEditCss from "js-hex-editor/dist/hex-editor.css?inline";
import { HexEditor } from "js-hex-editor";

@customElement("hex-editor")
export class OpenFileButton extends LitElement {
  @property({ type: String })
  data = "";

  private editor: HexEditor | null = null;

  static styles = css`
    :host {
      background-color: var(--background-color);
      color: var(--text-color);
    }
    :host > main {
      border: none !important;
    }
    main > header {
      display: none !important;
    }
    main > footer {
      box-shadow: none !important;
      border-top: solid 1px var(--border-color) !important;
    }
    .hex-row-offset {
      border-right: solid 1px var(--border-color);
    }
    span[data-position]:focus {
      color: var(--text-color-tertiary);
    }
    .hex-row-data > main:nth-child(4),
    .hex-row-data > main:nth-child(8),
    .hex-row-data > main:nth-child(12),
    .hex-row-data > main:nth-child(16),
    .hex-row-data > main:nth-child(20),
    .hex-row-data > main:nth-child(24) {
      margin-right: 1ch;
    }
    ${unsafeCSS(hexEditCss)}
  `;

  firstUpdated(_changedProperties: PropertyValues): void {}

  updated(prev: PropertyValues) {
    if (prev.has("data")) {
      this.shadowRoot?.querySelector("main")?.remove();
      this.editor = new HexEditor({
        target: this.shadowRoot,
        props: {
          bytesPerLine: 28,
          readonly: true,
          width: "100%",
          height: "100%",
          data: base64ToArrayBuffer(this.data)
        }
      });
    }
  }
}

function base64ToArrayBuffer(base64: string) {
  var binaryString = atob(base64);
  var bytes = new Uint8Array(binaryString.length);
  for (var i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}
