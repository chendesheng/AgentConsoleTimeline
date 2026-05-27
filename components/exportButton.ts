import { html, LitElement, PropertyValues } from "lit";
import { customElement, property, state } from "lit/decorators.js";
import { create7zArchive, getArchiveErrorMessage } from "./js7z";

@customElement("export-button")
export class ExportButton extends LitElement {
  @property({ type: String })
  label = "";

  @property({ type: String })
  fileName = "";

  @property({ type: String })
  fileContent = "";

  @state()
  private exporting = false;

  private waiting = false;

  async export() {
    const blob = await create7zArchive(this.fileName, this.fileContent);
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = this.fileName + ".7z";
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30 * 1000);
  }

  async handleClick(e: MouseEvent) {
    if (this.exporting) {
      e.preventDefault();
      e.stopPropagation();
      return;
    }

    if (!this.fileContent) {
      // this is a hack to wait for the file content to be set
      this.waiting = true;
      this.exporting = true;
      return;
    }

    e.preventDefault();
    e.stopPropagation();
    try {
      this.exporting = true;
      await this.export();
    } catch (error) {
      this.dispatchEvent(
        new CustomEvent("error", {
          detail: `Export failed: ${getArchiveErrorMessage(error)}`,
          bubbles: true,
        }),
      );
    } finally {
      this.exporting = false;
    }
  }

  protected createRenderRoot(): HTMLElement | DocumentFragment {
    return this;
  }

  render() {
    return html`<div>
      <button class="text" ?disabled=${this.exporting} @click=${this.handleClick}>
        <i class="icon export"></i>${this.exporting
          ? "Exporting..."
          : this.label}
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
      this.export().catch((error) => {
        this.dispatchEvent(
          new CustomEvent("error", {
            detail: `Export failed: ${getArchiveErrorMessage(error)}`,
            bubbles: true,
          }),
        );
      }).finally(() => {
        this.exporting = false;
      });
    }
  }
}
