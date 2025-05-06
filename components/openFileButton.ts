import { css, html, LitElement, unsafeCSS } from "lit";
import { customElement, property } from "lit/decorators.js";
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

    .icon.import {
      background-color: currentColor;
      mask: url("${unsafeCSS(importUrl)}") no-repeat 100% 100%;
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
        ${this.icon ? html`<i class="icon ${this.icon}"></i>` : ""}${this.label}
      </button>
    </div>`;
  }
}
