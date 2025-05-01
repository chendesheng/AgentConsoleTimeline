import { unzipFilesAndCreateCustomEvent } from "./unzipFile";

export class DropZipFile extends HTMLElement {
  connectedCallback() {
    this.addEventListener(
      "dragenter",
      (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (!this.classList.contains("drop-file-container--hover")) {
          this.classList.add("drop-file-container--hover");
        }
      },
      { capture: true },
    );

    this.addEventListener(
      "dragover",
      (e: DragEvent) => {
        e.preventDefault();
        e.stopPropagation();
        if (!this.classList.contains("drop-file-container--hover")) {
          this.classList.add("drop-file-container--hover");
        }
      },
      { capture: true },
    );

    this.addEventListener("dragleave", (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();

      const next = e.relatedTarget as Node | null;
      if (next && this.contains(next)) return; // still inside

      this.classList.remove("drop-file-container--hover");
    });

    this.addEventListener(
      "drop",
      async (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.classList.remove("drop-file-container--hover");

        const files = e.dataTransfer?.files;
        if (!files) return;

        const event = await unzipFilesAndCreateCustomEvent(files);
        this.dispatchEvent(event);
      },
      { capture: true },
    );
  }
}

customElements.define("drop-zip-file", DropZipFile);
