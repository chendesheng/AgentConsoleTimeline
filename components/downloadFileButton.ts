import { css, html, LitElement, unsafeCSS } from "lit";
import { customElement, property } from "lit/decorators.js";
import { writeTextFile, BaseDirectory } from "@tauri-apps/plugin-fs";
import exportUrl from "../assets/images/Export.svg";
import { save } from "@tauri-apps/plugin-dialog";

@customElement("download-file-button")
export class DownloadFileButton extends LitElement {
  @property({ type: String })
  name = "";

  @property({ type: String })
  label = "";

  @property({ type: String })
  content = "";

  @property({ type: String })
  icon = "";

  async handleClick(e: Event) {
    e.preventDefault();
    e.stopPropagation();
    if (window.isTauri) {
      const path = await save({
        filters: [
          {
            name: this.name,
            extensions: ["har", "json"],
          },
        ],
      });
      await writeTextFile(this.name, this.content, {
        baseDir: BaseDirectory.Download,
      });
      return;
    }

    const link = document.createElement("A");
    link.setAttribute("download", "download");
    const href = URL.createObjectURL(new Blob([this.content]));
    link.setAttribute("href", href);
    link.click();
    URL.revokeObjectURL(href);
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
    return html`<button class="text" @click=${this.handleClick}>
      ${this.icon ? html`<i class="icon ${this.icon}"></i>` : ""}${this.label}
    </button>`;
  }
}
