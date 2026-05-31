import { css, html, LitElement, unsafeCSS } from "lit";
import { customElement, property, query } from "lit/decorators.js";
import { unzipFilesAndCreateCustomEvent } from "./unzipFile";
import importUrl from "../assets/images/Import.svg";

@customElement("open-file-button")
export class OpenFileButton extends LitElement {
  @property({ type: String })
  label = "";

  @property({ type: String })
  error = "";

  @property({ type: String })
  icon = "";

  @property({ type: Boolean })
  disabled = false;

  async handleChange(e: Event) {
    e.preventDefault();
    e.stopPropagation();

    const input = e.currentTarget as HTMLInputElement;

    const files = input.files;
    if (!files) return;

    this.dispatchEvent(
      new CustomEvent("setOpeningFile", { detail: files[0].name }),
    );

    const event = await unzipFilesAndCreateCustomEvent(files);
    this.dispatchEvent(event);

    input.onchange = null;
  }

  createRenderRoot(): HTMLElement | DocumentFragment {
    return this;
  }

  connectedCallback(): void {
    super.connectedCallback();
    this.handleChange = this.handleChange.bind(this);
  }

  handleClick() {
    if (this.disabled) return;

    const input = document.createElement("input");
    input.type = "file";
    input.onchange = this.handleChange;
    input.click();
  }

  render() {
    return html`<div title=${this.error}>
      <button
        class="text ${this.error ? "error" : ""}"
        ?disabled=${this.disabled}
        @click=${this.handleClick}
      >
        ${this.icon ? html`<i class="icon ${this.icon}"></i>` : ""}${this.label}
      </button>
    </div>`;
  }
}
