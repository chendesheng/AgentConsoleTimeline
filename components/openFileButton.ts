import { css, html, LitElement } from "lit";
import { customElement, property } from "lit/decorators.js";
import { unzipFilesAndCreateCustomEvent } from "./unzipFile";

@customElement("open-file-button")
export class OpenFileButton extends LitElement {
  @property({ type: String })
  label = "";

  @property({ type: String })
  error = "";

  async handleChange(e: Event) {
    e.preventDefault();
    e.stopPropagation();

    const files = (e.target as HTMLInputElement).files;
    if (!files) return;

    const event = await unzipFilesAndCreateCustomEvent(files);
    this.dispatchEvent(event);
  }

  static styles = css`
    input[type="file"] {
      display: none;
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
  `;

  handleClick() {
    this.shadowRoot?.querySelector("input")?.click();
  }

  render() {
    return html`<div title=${this.error}>
      <input type="file" @change=${this.handleChange} />
      <button
        class="text ${this.error ? "error" : ""}"
        @click=${this.handleClick}
      >
        ${this.label}
      </button>
    </div>`;
  }
}
