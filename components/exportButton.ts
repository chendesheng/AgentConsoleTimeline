import { html, LitElement, PropertyValues } from "lit";
import { customElement, property, state } from "lit/decorators.js";
import ExportWorker from "./exportWorker?worker";

type ExportResponse =
  | { ok: true; blob: Blob }
  | { ok: false; error: string };

@customElement("export-button")
export class ExportButton extends LitElement {
  @property({ type: String })
  label = "";

  @property({ type: String })
  fileName = "";

  @property({ type: String })
  fileContent = "";

  @property({ type: String })
  error = "";

  @state()
  private exporting = false;

  private waiting = false;

  async export() {
    const blob = await create7zArchiveInWorker(this.fileName, this.fileContent);
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = this.fileName + ".7z";
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30 * 1000);
  }

  private dispatchExportStart() {
    this.dispatchEvent(new CustomEvent("export-start", { bubbles: true }));
  }

  private dispatchExportError(error: unknown) {
    this.dispatchEvent(
      new CustomEvent("export-error", {
        detail: error instanceof Error ? error.message : String(error),
        bubbles: true,
      }),
    );
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
      this.dispatchExportStart();
      return;
    }

    e.preventDefault();
    e.stopPropagation();
    try {
      this.exporting = true;
      this.dispatchExportStart();
      await this.export();
    } catch (error) {
      this.dispatchExportError(error);
    } finally {
      this.exporting = false;
    }
  }

  protected createRenderRoot(): HTMLElement | DocumentFragment {
    return this;
  }

  render() {
    return html`<div title=${this.error}>
      <button
        class=${this.error ? "text error" : "text"}
        ?disabled=${this.exporting}
        @click=${this.handleClick}
      >
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
        this.dispatchExportError(error);
      }).finally(() => {
        this.exporting = false;
      });
    }
  }
}

async function create7zArchiveInWorker(fileName: string, fileContent: string) {
  const worker = new ExportWorker();

  return await new Promise<Blob>((resolve, reject) => {
    worker.onmessage = (event: MessageEvent<ExportResponse>) => {
      worker.terminate();

      if (event.data.ok) {
        resolve(event.data.blob);
      } else {
        reject(new Error(event.data.error));
      }
    };

    worker.onerror = (event) => {
      worker.terminate();
      reject(new Error(event.message || "Export failed: worker error"));
    };

    worker.postMessage({ fileName, fileContent });
  });
}
