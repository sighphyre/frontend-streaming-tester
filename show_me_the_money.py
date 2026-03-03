import pandas as pd
import matplotlib.pyplot as plt

# Load results
df = pd.read_csv("results.csv")

# Derived metrics
df["ss_rbtb_mb"] = df["ss_rbtb_bytes"] / (1024 * 1024)
df["edge_rss_mb"] = df["edge_rss_kb"] / 1024

PAGE_SIZE = 4096
df["tcp_mem_mb_est"] = df["sockstat_tcp_mem_pages"] * PAGE_SIZE / (1024 * 1024)

# --- Plot 1: Kernel socket buffers ---
plt.figure()
plt.plot(df["target_conns"], df["ss_rbtb_mb"], marker="o")
plt.grid(True)
plt.xlabel("Target connections")
plt.ylabel("Sum of rb+tb (MB)")
plt.title("Kernel socket buffer usage vs SSE connections (Linear)")
plt.tight_layout()
plt.savefig("kernel_buffers_linear.png", dpi=150)
plt.close()

# --- Plot 2: Edge RSS ---
plt.figure()
plt.plot(df["target_conns"], df["edge_rss_mb"], marker="o")
plt.grid(True)
plt.xlabel("Target connections")
plt.ylabel("Edge RSS (MB)")
plt.title("Edge RSS vs SSE connections (Linear)")
plt.tight_layout()
plt.savefig("edge_rss_linear.png", dpi=150)
plt.close()

# --- Plot 3: Total TCP mem ---
plt.figure()
plt.plot(df["target_conns"], df["tcp_mem_mb_est"], marker="o")
plt.grid(True)
plt.xlabel("Target connections")
plt.ylabel("sockstat TCP mem (MB, est)")
plt.title("Total TCP memory vs SSE connections (Linear)")
plt.tight_layout()
plt.savefig("tcp_mem_linear.png", dpi=150)
plt.close()

df.to_csv("results_enriched.csv", index=False)

print("Linear plots written:")
print(" - kernel_buffers_linear.png")
print(" - edge_rss_linear.png")
print(" - tcp_mem_linear.png")