import { html, HTMLTemplateResult } from "lit";
import { jsonType, JsonType, ROW_HEIGHT } from "./model";

export function leafValueRenderer(
  value: JsonType,
  soundUrl: string,
  pathStr: string,
): HTMLTemplateResult {
  if (typeof value === "string") {
    if (
      URL.canParse(value) &&
      (/Global\/agents\/[0-9a-fA-F-]+\/avatar/i.test(value) ||
        /.svg$/.test(value) ||
        /\/chatbots\/([^\/]+)\/avatar\?/.test(value))
    ) {
      return html`<a class="avatar" href="${value}" target="_blank"
        ><img src="${value}" height="${ROW_HEIGHT}"
      /></a>`;
    } else if (URL.canParse(value)) {
      return html`<span class="value string"
        >"<a href="${value}" target="_blank">${value}</a>"</span
      >`;
    } else if (
      pathStr.endsWith(".agentConsoleLogoCodeSnippet") ||
      pathStr.endsWith(".controlPanelLogoCodeSnippet")
    ) {
      const anchorName = `--preview-${pathStr}`;
      const id = `html-preview-${pathStr}`;
      return html`<span class="value ${jsonType(value)}"
        ><button
          popovertarget="${id}"
          class="preview"
          style="anchor-name: ${anchorName};"
        ></button>
        <div
          id="${id}"
          class="html-preview ${pathStr.slice(pathStr.lastIndexOf(".") + 1)}"
          style="position-anchor: ${anchorName}; top: calc(anchor(bottom) + 4px); left: anchor(left); position-try-fallbacks: flip-block;"
          popover="auto"
          .innerHTML=${value}
        ></div>
        ${JSON.stringify(value)}</span
      >`;
    } else if (
      pathStr.endsWith(".notificationIcon") ||
      pathStr.endsWith(".ico") ||
      pathStr.endsWith(".faviconImage")
    ) {
      return html`<img
        class="image-preview"
        src="${`data:image/png;base64,${value}`}"
        height="${ROW_HEIGHT}"
      />`;
    } else if (
      /^#[0-9a-fA-F]{6}$/.test(value) ||
      /^#[0-9a-fA-F]{3}$/.test(value) ||
      /^rgba\(\s*[0-9]+,\s*[0-9]+,\s*[0-9]+,\s*[0-9.]+\s*\)$/.test(value) ||
      /^rgb\(\s*[0-9]+,\s*[0-9]+,\s*[0-9]+\s*\)$/.test(value)
    ) {
      // FIXME: add alpha
      return html`<span class="value ${jsonType(value)}"
        ><input
          type="color"
          value="${value.startsWith("rgb")
            ? rgbaToHex(value)
            : expandHex(value)}"
        />
        ${JSON.stringify(value)}</span
      >`;
    } else if (
      (pathStr.startsWith("config.settings.sound") &&
        pathStr.endsWith(".id")) ||
      (pathStr.startsWith("config.preference") && pathStr.endsWith("SoundId"))
    ) {
      return html`<span class="value ${jsonType(value)}"
        ><button
          class="play-sound"
          @click=${(e: MouseEvent) => {
            const button = e.currentTarget as HTMLButtonElement;
            button.classList.toggle("playing");

            const audio = document.createElement("audio");
            audio.src = soundUrl.replace("{soundId}", value);
            audio.onended = () => button.classList.remove("playing");
            audio.onerror = () => button.classList.remove("playing");
            audio.play();
          }}
        ></button
        >${JSON.stringify(value)}</span
      >`;
    }
  }

  return html`<span class="value ${jsonType(value)}"
    >${JSON.stringify(value)}</span
  >`;
}

function expandHex(hex: string) {
  if (hex.length === 4) {
    return `#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}`;
  }
  return hex;
}

function rgbaToHex(rgba: string) {
  const [r, g, b] = rgba.match(/\d+/g)!.map(Number);
  return `#${r.toString(16)}${g.toString(16)}${b.toString(16)}`;
}
