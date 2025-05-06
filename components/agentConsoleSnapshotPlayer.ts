import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";

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
      opacity: 0.3;
    }
    button.reset,
    button.reveal {
      font-size: 18px;
      font-weight: 500;
      line-height: 0px;
      padding: 0;
    }
  `;

  private handleClickReset() {
    this.initById(this.initialId);
  }

  private handleClickScroll() {
    this.dispatchEvent(new CustomEvent("scrollToCurrent", { detail: {} }));
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

  render() {
    return html`<div
      class="container"
      @keydown=${this.handleKeyDown}
      tabindex="0"
      style="--hairline: ${1 / window.devicePixelRatio}px"
    >
      <button @click=${this.handleClickPlay}>
        ${this.playingState === "live"
          ? "🔴"
          : this.playingState === "playing" && !this.isSeeking
          ? "❚❚"
          : "▶"}
      </button>
      <button class="reset" @click=${this.handleClickReset}>↺</button>
      <button class="reveal" @click=${this.handleClickScroll}>⇱</button>
      <div class="track" @mousedown=${this.handleMouseDownTrack}>
        <div
          class="currentTime"
          style="left: ${this.getTimePosPercent(this.time)}"
        ></div>
        ${this.items.map(
          (item) =>
            html`<div
              class=${this.highlightVisitorId
                ? item.comment?.includes(this.highlightVisitorId)
                  ? ""
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
