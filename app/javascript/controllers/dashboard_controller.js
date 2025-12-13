import { Controller } from "@hotwired/stimulus";
import { createConsumer } from "@rails/actioncable";

export default class extends Controller {
  static targets = [
    "sidebar",
    "overlay",
    "contentArea",
    "connectionStatus",
    "currentTime",
    "statValue",
    "livePositionsTable",
    "paperPositionsTable",
  ];

  static values = {
    channel: String,
  };

  connect() {
    this.updateTime();
    this.timeInterval = setInterval(() => this.updateTime(), 1000);

    // Connect to ActionCable
    if (this.channelValue) {
      this.connectToChannel();
    }
  }

  disconnect() {
    if (this.timeInterval) {
      clearInterval(this.timeInterval);
    }

    if (this.subscription) {
      this.subscription.unsubscribe();
    }

    if (this.consumer) {
      this.consumer.disconnect();
    }
  }

  toggleSidebar() {
    this.sidebarTarget.classList.toggle("active");
    this.overlayTarget.classList.toggle("active");
  }

  closeSidebar() {
    this.sidebarTarget.classList.remove("active");
    this.overlayTarget.classList.remove("active");
  }

  updateTime() {
    const now = new Date();
    const timeString = now.toLocaleTimeString("en-US", {
      hour12: false,
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });

    if (this.hasCurrentTimeTarget) {
      this.currentTimeTarget.textContent = timeString;
    }
  }

  connectToChannel() {
    this.consumer = createConsumer();

    this.subscription = this.consumer.subscriptions.create(
      { channel: this.channelValue },
      {
        connected: () => {
          console.log("Connected to ActionCable");
          this.updateConnectionStatus(true);
        },

        disconnected: () => {
          console.log("Disconnected from ActionCable");
          this.updateConnectionStatus(false);
        },

        received: (data) => {
          this.handleUpdate(data);
        },
      }
    );
  }

  updateConnectionStatus(connected) {
    if (!this.hasConnectionStatusTarget) return;

    const indicator =
      this.connectionStatusTarget.querySelector(".status-indicator");
    const text = this.connectionStatusTarget.querySelector(".status-text");

    if (indicator) {
      indicator.classList.toggle("connected", connected);
      indicator.classList.toggle("disconnected", !connected);
    }

    if (text) {
      text.textContent = connected ? "Connected" : "Disconnected";
    }
  }

  handleUpdate(data) {
    // Handle different types of updates
    switch (data.type) {
      case "position_update":
        this.updatePosition(data.position);
        break;
      case "signal_update":
        this.updateSignal(data.signal);
        break;
      case "order_update":
        this.updateOrder(data.order);
        break;
      case "stats_update":
        this.updateStats(data.stats);
        break;
      case "screener_update":
        this.handleScreenerUpdate(data);
        break;
      default:
        console.log("Unknown update type:", data.type);
    }
  }

  handleScreenerUpdate(data) {
    // Show notification that screener completed
    if (data.screener_type && data.candidate_count !== undefined) {
      const message = `${data.screener_type} screener completed: Found ${data.candidate_count} candidates`;
      console.log(message);

      // Reload page after a short delay to show results
      setTimeout(() => {
        if (window.location.pathname.includes("screener")) {
          window.location.reload();
        }
      }, 2000);
    }
  }

  updatePosition(position) {
    // Find and update position row in tables
    const row = document.querySelector(`tr[data-position-id="${position.id}"]`);
    if (!row) return;

    // Update current price and P&L
    const currentPriceCell = row.querySelector("td:nth-child(5)");
    const pnlCell = row.querySelector("td:nth-child(6)");

    if (currentPriceCell) {
      currentPriceCell.textContent = `₹${parseFloat(
        position.current_price
      ).toFixed(2)}`;
    }

    if (pnlCell) {
      const pnl = parseFloat(position.unrealized_pnl);
      pnlCell.textContent = `₹${pnl.toFixed(0)}`;
      pnlCell.className = pnl >= 0 ? "text-success" : "text-danger";
    }

    // Add flash animation
    row.classList.add("updated");
    setTimeout(() => row.classList.remove("updated"), 1000);
  }

  updateSignal(signal) {
    // Update signal in the list
    const signalElement = document.querySelector(
      `div[data-signal-id="${signal.id}"]`
    );
    if (!signalElement) return;

    // Update execution status
    const badge = signalElement.querySelector(".badge");
    if (badge && signal.executed) {
      badge.className = "badge bg-success";
      badge.textContent = "Executed";
    }

    signalElement.classList.add("updated");
    setTimeout(() => signalElement.classList.remove("updated"), 1000);
  }

  updateOrder(order) {
    // Update order in the list
    const orderElement = document.querySelector(
      `div[data-order-id="${order.id}"]`
    );
    if (!orderElement) return;

    // Update status badge
    const badge = orderElement.querySelector(".badge");
    if (badge) {
      const statusClasses = {
        executed: "bg-success",
        rejected: "bg-danger",
        cancelled: "bg-secondary",
        pending: "bg-warning",
      };
      badge.className = `badge ${
        statusClasses[order.status] || "bg-secondary"
      }`;
      badge.textContent =
        order.status.charAt(0).toUpperCase() + order.status.slice(1);
    }

    orderElement.classList.add("updated");
    setTimeout(() => orderElement.classList.remove("updated"), 1000);
  }

  updateStats(stats) {
    // Update stat cards
    Object.keys(stats).forEach((statKey) => {
      const statElement = document.querySelector(`[data-stat="${statKey}"]`);
      if (statElement) {
        statElement.textContent = stats[statKey];
      }
    });
  }
}
