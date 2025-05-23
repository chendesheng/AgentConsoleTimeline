import { html, css, LitElement, PropertyValues, unsafeCSS } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import reloadToolbar from "../assets/images/ReloadToolbar.svg";
import crosshair from "../assets/images/Crosshair.svg";
import record from "../assets/images/Record.svg";
import auditStart from "../assets/images/AuditStart.svg";
import auditStop from "../assets/images/AuditStop.svg";

type PlayingState = "paused" | "playing" | "live";

@customElement("agent-console-snapshot-player")
export class AgentConsoleSnapshotPlayer extends LitElement {
  @property({ type: Array })
  items: { id: string; time: number; comment?: string }[] = [];

  @property({ type: Number })
  max: number = 0;

  @property({ type: String })
  initialId = "";

  @property({ type: String })
  highlightVisitorId = "";

  @property({ type: Boolean })
  allowLive = false;

  @state()
  private time: number = 0;
  @state()
  private index: number = 0;
  @state()
  private playingState = "paused";

  @state()
  private isSeeking: boolean = false;

  private get isPlayingOrSeeking() {
    return this.playingState === "playing" || this.isSeeking;
  }

  private timer: any;

  static styles = css`
    .container {
      display: flex;
      align-items: center;
      flex-flow: row nowrap;
      height: 20px;
      gap: 4px;
      width: 100%;
      --current-time-color: grey;
      user-select: none;
      -webkit-user-select: none;
      -moz-user-select: none;
    }

    .container:focus {
      outline: none;
      --current-time-color: red;
    }

    .container > button {
      flex: none;
      margin: 0;
      outline: none;
      border: none;
      border-radius: 2px;
      width: 24px;
      height: 18px;
    }

    .container > time {
      width: 6ch;
    }

    .track {
      display: flex;
      position: relative;
      border: 1px solid white;
      border-radius: 2px;
      height: 20px;
      flex: auto;
      box-sizing: border-box;
    }

    .track > div {
      position: absolute;
      top: 0;
      bottom: 0;
      width: var(--hairline);
      background-color: white;
      pointer-events: none;
    }

    .track > div.currentTime {
      background-color: var(--current-time-color, red);
      z-index: 1;
    }
    .track > div.currentTime::before {
      content: "";
      position: absolute;
      top: -1px;
      left: -2.5px;
      width: 6px;
      height: 0px;
      border-top: 1px solid var(--current-time-color, red);
    }
    .track > div.currentTime::after {
      content: "";
      position: absolute;
      bottom: -1px;
      left: -2.5px;
      width: 6px;
      height: 0px;
      border-top: 1px solid var(--current-time-color, red);
    }
    .track > div.darken {
      opacity: 0.5;
    }
    .track > div.highlight {
      background-color: red;
    }
    button.reset,
    button.reveal {
      font-size: 18px;
      font-weight: 500;
      line-height: 0px;
      padding: 0;
    }

    .icon {
      display: inline-block;
      fill: currentColor;
      vertical-align: middle;
      overflow: hidden;
      flex: none;
      color: currentColor;
      background-color: currentColor;
      width: 13px;
      height: 13px;
    }

    .icon.reset {
      mask: url("${unsafeCSS(reloadToolbar)}");
      transform: rotate(200deg) scaleY(-1);
    }
    .icon.crosshair {
      mask: url("${unsafeCSS(crosshair)}");
    }
    .icon.auditStart {
      mask: url("${unsafeCSS(auditStart)}");
    }
    .icon.auditStop {
      mask: url("${unsafeCSS(auditStop)}");
    }
    .icon.auditStart,
    .icon.auditStop,
    .icon.record {
      position: relative;
      top: -1px;
      width: 12px;
      height: 12px;
    }
    .icon.record {
      content: url("${unsafeCSS(record)}");
      background: none;
    }
  `;

  private handleClickReset() {
    this.initById(this.initialId);
    this.container?.focus();
  }

  private handleClickScroll() {
    this.dispatchEvent(new CustomEvent("scrollToCurrent", { detail: {} }));
    this.container?.focus();
  }

  private fireIndexChange() {
    const id = this.items[this.index]!.id;
    this.dispatchEvent(
      new CustomEvent("change", {
        detail: { id },
      }),
    );
  }

  private handleClickPlay() {
    this.togglePlayingState();
    this.container?.focus();
  }

  private updateIndex(index: number) {
    // console.log("updateIndex", index);
    const i = clamp(index, 0, this.items.length - 1);
    if (i !== index) this.playingState = "paused";
    this.index = i;
  }

  private updateTime(time: number) {
    time = clamp(time, 0, +this.max);
    if (this.time === time) return;
    this.time = time;
  }

  private updateTimePx(mouseX: number, rect: DOMRect) {
    const x = mouseX - rect.left;
    const pos = x / rect.width;
    this.updateTime(+this.max * pos);
  }

  private handleMouseDownTrack(e: MouseEvent) {
    if (this.playingState === "live") return;
    if (this.isSeeking) return;

    this.isSeeking = true;
    const rect = (e.target as HTMLElement).getBoundingClientRect();
    this.updateTimePx(e.clientX, rect);

    const overlay = document.createElement("div");
    overlay.style.cssText = `position: fixed; top: 0; left: 0; right: 0; bottom: 0;`;
    document.body.append(overlay);

    const handleMouseMove = (e: MouseEvent) => {
      if (e.buttons === 0) {
        this.isSeeking = false;
        cancel();
        return;
      } else if (e.buttons === 1) {
        if (!this.isSeeking) return;
        this.updateTimePx(e.clientX, rect);
      }
    };

    const handleMouseUp = (_e: MouseEvent) => {
      if (!this.isSeeking) return;
      this.isSeeking = false;
      cancel();
    };

    const cancel = () => {
      overlay.remove();
      document.removeEventListener("mousemove", handleMouseMove);
      document.removeEventListener("mouseup", handleMouseUp);
    };

    document.addEventListener("mousemove", handleMouseMove);
    document.addEventListener("mouseup", handleMouseUp);
  }

  private handleMouseMoveTrack(e: MouseEvent) {
    if (e.buttons !== 0) return;
    const rect = (e.target as HTMLElement).getBoundingClientRect();
    const x = e.clientX - rect.x;
    const pos = x / rect.width;
    const time = clamp(+this.max * pos, 0, +this.max);
    const index = this.timeToIndex(time);
    this.dispatchEvent(
      new CustomEvent("hover", {
        detail: {
          clientX: e.clientX,
          id: this.items[index]!.id,
        },
      }),
    );
  }

  private handleMouseLeaveTrack() {
    this.dispatchEvent(new CustomEvent("unhover"));
  }

  private togglePlayingState() {
    if (this.playingState === "paused") {
      this.playingState = "playing";
    } else if (this.playingState === "playing") {
      this.playingState = this.allowLive ? "live" : "paused";
    } else {
      this.playingState = "paused";
    }
  }

  private handleKeyDown(e: KeyboardEvent) {
    if (e.key === " ") {
      this.togglePlayingState();
    } else if (e.key === "s") {
      this.handleClickScroll();
    } else if (e.key === "r") {
      this.handleClickReset();
    }

    if (!this.isPlayingOrSeeking) {
      if (e.key === "ArrowLeft" || e.key === "h") {
        this.updateIndex(this.index - 1);
        // this.handleClickScroll();
      } else if (e.key === "ArrowRight" || e.key === "l") {
        this.updateIndex(this.index + 1);
        // this.handleClickScroll();
      }
    }
  }

  private getTimePosPercent(time: number) {
    return `${(time / this.max) * 100}%`;
  }

  @query(".container")
  private container?: HTMLDivElement;

  render() {
    return html`<div
      class="container"
      @keydown=${this.handleKeyDown}
      tabindex="0"
      style="--hairline: ${1 / window.devicePixelRatio}px"
    >
      <button @click=${this.handleClickPlay}>
        ${this.playingState === "live"
          ? html`<i class="icon record"></i>`
          : this.playingState === "playing" && !this.isSeeking
          ? html`<i class="icon auditStop"></i>`
          : html`<i class="icon auditStart"></i>`}
      </button>
      <button class="reset" @click=${this.handleClickReset}>
        <i class="icon reset"></i>
      </button>
      <button class="reveal" @click=${this.handleClickScroll}>
        <i class="icon crosshair"></i>
      </button>
      <div
        class="track"
        @mousedown=${this.handleMouseDownTrack}
        @mousemove=${this.handleMouseMoveTrack}
        @mouseleave=${this.handleMouseLeaveTrack}
      >
        <div
          class="currentTime"
          style="left: ${this.getTimePosPercent(this.time)}"
        ></div>
        ${this.items.map(
          (item) =>
            html`<div
              class=${this.highlightVisitorId
                ? item.comment?.includes(this.highlightVisitorId)
                  ? "highlight"
                  : "darken"
                : ""}
              style="left: ${this.getTimePosPercent(item.time)}"
            ></div>`,
        )}
      </div>
      <time>${((this.time - this.max) / 1000).toFixed(1)}s</time>
    </div>`;
  }

  private timeToIndex(time: number) {
    const i = this.items.findIndex((item) => time < item.time);
    // console.log("timeToIndex", time, i);
    return clamp(i - 1, 0, this.items.length - 1);
  }
  private indexToTime(index: number) {
    const time = this.items[index]?.time || this.items[0].time;
    // console.log("indexToTime", index, time);
    return time;
  }

  private initById(entryId: string) {
    // console.log("initById", entryId);

    this.playingState = "paused";
    this.isSeeking = false;
    this.index = this.items.findIndex(({ id }) => id === entryId);
    this.time = this.indexToTime(this.index);
  }

  protected updated(changedProperties: PropertyValues): void {
    // console.log("updated", changedProperties);

    if (changedProperties.has("items")) {
      this.items.sort((a, b) => a.time - b.time);
      if (this.playingState === "live") {
        this.index = this.items.length - 1;
      }
    }

    if (changedProperties.has("initialId")) {
      this.initById(this.initialId);
    }

    if (
      changedProperties.has("playingState") ||
      changedProperties.has("isSeeking")
    ) {
      if (this.playingState === "playing" && !this.isSeeking) {
        this.timer = setInterval(() => {
          this.updateTime(this.time + 50);
        }, 50);
      } else {
        clearInterval(this.timer);
        this.timer = null;
      }
    }

    if (changedProperties.has("time")) {
      if (this.isPlayingOrSeeking) {
        this.index = this.timeToIndex(this.time);
      }
    }

    if (changedProperties.has("index")) {
      if (!this.isPlayingOrSeeking) {
        this.time = this.indexToTime(this.index);
      }
      this.fireIndexChange();
    }
  }
}

function clamp(number: number, min: number, max: number) {
  return Math.max(min, Math.min(number, max));
}
