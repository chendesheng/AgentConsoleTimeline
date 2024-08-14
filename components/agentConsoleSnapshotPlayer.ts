import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, state } from "lit/decorators.js";

@customElement("agent-console-snapshot-player")
export class AgentConsoleSnapshotPlayer extends LitElement {
  @property({ type: Array })
  items: { id: string; time: number }[] = [];

  @property({ type: Number })
  min: number = 0;

  @property({ type: Number })
  max: number = 0;

  @property({ type: Number })
  initialTime: number = 0;

  @state()
  private time: number = 0;
  @state()
  private isPlaying: boolean = false;
  @state()
  private isSeeking: boolean = false;
  private timer: any;

  static styles = css`
    .container {
      display: flex;
      align-items: center;
      flex-flow: row nowrap;
      height: 20px;
      gap: 4px;
      width: 100%;
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
      width: 1px;
      background-color: white;
      pointer-events: none;
    }

    .track > div.currentTime {
      background-color: red;
      z-index: 1;
    }
    .track > div.currentTime::before {
      content: "";
      position: absolute;
      top: -1px;
      left: -2.5px;
      width: 6px;
      height: 0px;
      border-top: 1px solid red;
    }
    .track > div.currentTime::after {
      content: "";
      position: absolute;
      bottom: -1px;
      left: -2.5px;
      width: 6px;
      height: 0px;
      border-top: 1px solid red;
    }
    button.reset,
    button.reveal {
      font-size: 22px;
      line-height: 0px;
      padding: 0;
    }
    .container > time {
      width: 6ch;
    }
  `;

  private handleClickReset() {
    this.time = this.initialTime;
    this.isPlaying = false;
    clearInterval(this.timer);
    this.fireTimeChange();
  }

  private handleClickScroll() {
    this.dispatchEvent(new CustomEvent("scrollToCurrent", { detail: {} }));
  }

  private prevId?: string;
  private fireTimeChange() {
    if (this.prevId === this.getCurrentItem()?.id) {
      return;
    }

    this.prevId = this.getCurrentItem()?.id;
    // console.log("timeChange", this.prevId);
    this.getCurrentItem()?.id;
    this.dispatchEvent(
      new CustomEvent("timeChange", {
        detail: { id: this.prevId }
      })
    );
  }

  private handleIsPlayingChanged() {
    // console.log("handleIsPlayingChange", this.isPlaying, this.isSeeking);
    if (this.isPlaying && !this.isSeeking) {
      this.timer = setInterval(() => {
        this.updateTime(this.time + 50);
        this.fireTimeChange();
      }, 50);
    } else {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private handleClickPlay() {
    this.isPlaying = !this.isPlaying;
    this.handleIsPlayingChanged();
  }

  private updateTime(time: number) {
    time = clamp(time, +this.min, +this.max);
    if (this.time === time) return;
    this.time = time;
    this.fireTimeChange();

    if (this.time >= +this.max) {
      this.isPlaying = false;
      this.handleIsPlayingChanged();
    }
  }

  private updateTimePx(e: MouseEvent) {
    const rect = (e.target as HTMLElement).getBoundingClientRect();
    const x = e.clientX - rect.left;
    const pos = x / rect.width;
    this.updateTime(+this.min + (+this.max - this.min) * pos);
  }

  private getTimePosPercent(time: number) {
    // console.log(time, this.min, this.max);
    return `${((time - this.min) / (this.max - this.min)) * 100}%`;
  }

  private handleMouseDownTrack(e: MouseEvent) {
    if (this.isSeeking) return;

    this.isSeeking = true;
    this.handleIsPlayingChanged();

    this.updateTimePx(e);
  }

  private handleMouseMoveTrack(e: MouseEvent) {
    if (e.buttons === 1) {
      this.updateTimePx(e);
    }
  }

  private handleMouseUpTrack(e: MouseEvent) {
    if (!this.isSeeking) return;

    this.isSeeking = false;
    this.handleIsPlayingChanged();
  }

  render() {
    return html`<div class="container">
      <button @click=${this.handleClickPlay}>
        ${this.isPlaying && !this.isSeeking ? "❚❚" : "▶"}
      </button>
      <button class="reset" @click=${this.handleClickReset}>↺</button>
      <button class="reveal" @click=${this.handleClickScroll}>⇱</button>
      <div
        class="track"
        @mousedown=${this.handleMouseDownTrack}
        @mousemove=${this.handleMouseMoveTrack}
        @mouseup=${this.handleMouseUpTrack}
      >
        <div
          class="currentTime"
          style="left: ${this.getTimePosPercent(this.time)}"
        ></div>
        ${this.items.map(
          (item) =>
            html`<div style="left: ${this.getTimePosPercent(item.time)}"></div>`
        )}
      </div>
      <time>${((this.time - this.max) / 1000).toFixed(1)}s</time>
    </div>`;
  }

  connectedCallback(): void {
    super.connectedCallback();
    this.time = +this.initialTime;
  }

  private getCurrentItem() {
    const i = this.items.findIndex((item) => this.time <= item.time);

    if (this.items[i].time === this.time) {
      return this.items[i];
    } else if (i > 0) {
      return this.items[i - 1];
    } else if (this.items.length > 0) {
      return this.items[0];
    }
  }

  protected update(changedProperties: PropertyValues): void {
    super.update(changedProperties);
    if (changedProperties.has("initialTime")) {
      this.isPlaying = false;
      this.isSeeking = false;
      this.time = +this.initialTime;
      this.handleIsPlayingChanged();
    }
  }
}

function clamp(number: number, min: number, max: number) {
  return Math.max(min, Math.min(number, max));
}
