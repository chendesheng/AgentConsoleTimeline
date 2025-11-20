import JSZip from "jszip";
import { css, html, LitElement, PropertyValues, unsafeCSS } from "lit";
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

  private waiting = false;

  async export() {
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
    a.download = this.fileName + ".zip";
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30 * 1000);
  }

  async handleClick(e: MouseEvent) {
    if (!this.fileContent) {
      // this is a hack to wait for the file content to be set
      this.waiting = true;
      return;
    }

    e.preventDefault();
    e.stopPropagation();
    await this.export();
  }

  protected createRenderRoot(): HTMLElement | DocumentFragment {
    return this;
  }

  render() {
    return html`<div>
      <button class="text" @click=${this.handleClick}>
        <i class="icon export"></i>${this.label}
      </button>
    </div>`;
  }

  updated(changedProperties: PropertyValues) {
    if (
      changedProperties.has("fileContent") &&
      !changedProperties.get("fileContent") &&
      this.fileContent &&
      this.waiting
    ) {
      this.waiting = false;
      this.export();
    }
  }
}
