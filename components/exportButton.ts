import JSZip from "jszip";
import { css, html, LitElement, unsafeCSS } from "lit";
import { customElement, property } from "lit/decorators.js";
import exportUrl from "../assets/images/Export.svg";

@customElement("export-button")
export class ExportButton extends LitElement {
  @property({ type: String })
  label = "";

  @property({ type: String })
  fileName = "";

  @property({ type: String })
  fileContent = "";

  async handleClick() {
    const zip = new JSZip();
    zip.file(this.fileName, this.fileContent, {
      compression: "DEFLATE",
      compressionOptions: {
        level: 9,
      },
    });
    const blob = await zip.generateAsync({ type: "blob" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = this.fileName;
    a.click();
    URL.revokeObjectURL(url);
  }

  static styles = css`
    input[type="file"] {
      display: none;
    }

    button {
      display: flex;
      align-items: center;
    }

    button .icon {
      margin-right: 2px;
    }

    button.text {
      font-size: 12px;
      background: none;
      border: none;
      cursor: pointer;
      padding: 0;
      color: inherit;
    }

    button.text:hover {
      color: var(--text-color);
    }

    button.error {
      color: var(--error-text-color);
    }

    button.error:hover {
      color: var(--error-text-color);
    }

    .icon {
      display: inline-block;
      width: 1em;
      height: 1em;
      fill: currentColor;
      vertical-align: middle;
      overflow: hidden;
      flex: none;
      color: currentColor;
    }

    .icon.export {
      background-color: currentColor;
      mask: url("${unsafeCSS(exportUrl)}") no-repeat 100% 100%;
    }
  `;

  render() {
    return html`<div>
      <button class="text" @click=${this.handleClick}>
        <i class="icon export"></i>${this.label}
      </button>
    </div>`;
  }
}
