import React, { useEffect, useState } from "react";
import axios from "axios";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer,
  Legend,
} from "recharts";

const BASE_API = "https://fire-backend-275g.onrender.com/api/fire-data/history";

const ranges = {
  "15s": 15,
  "15m": 900,
  "1h": 3600,
  "1d": 86400,
  "1w": 604800,
  "1y": 31536000,
};

export default function TemperatureChart() {
  const [data, setData] = useState([]);
  const [range, setRange] = useState("15m");

  const fetchData = async () => {
    try {
      const seconds = ranges[range];

      const [res1, res2] = await Promise.all([
        axios.get(`${BASE_API}/NODE_01/${seconds}`),
        axios.get(`${BASE_API}/NODE_02/${seconds}`),
      ]);

      // merge theo time index
      const map = {};

      res1.data.forEach((item) => {
        const t = item.createdAt.slice(11, 19);
        map[t] = { time: t, node1: item.temperature };
      });

      res2.data.forEach((item) => {
        const t = item.createdAt.slice(11, 19);
        if (!map[t]) map[t] = { time: t };
        map[t].node2 = item.temperature;
      });

      const merged = Object.values(map);
      setData(merged);
    } catch (err) {
      console.error(err);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, [range]);

  return (
    <div style={{ width: "100%", height: 350 }}>
      {" "}
      <h2>📈 Temperature Chart</h2>
      ```
      {/* RANGE SELECT */}
      <div style={{ marginBottom: 10 }}>
        {Object.keys(ranges).map((r) => (
          <button
            key={r}
            onClick={() => setRange(r)}
            style={{
              marginRight: 8,
              padding: "5px 10px",
              background: range === r ? "#1890ff" : "#eee",
              color: range === r ? "white" : "black",
              border: "none",
              borderRadius: 5,
              cursor: "pointer",
            }}
          >
            {r}
          </button>
        ))}
      </div>
      <ResponsiveContainer>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="time" />
          <YAxis />
          <Tooltip />
          <Legend />

          {/* NODE 1 */}
          <Line
            type="monotone"
            dataKey="node1"
            stroke="#ff4d4f"
            strokeWidth={2}
            dot={false}
            name="NODE_01"
          />

          {/* NODE 2 */}
          <Line
            type="monotone"
            dataKey="node2"
            stroke="#1890ff"
            strokeWidth={2}
            dot={false}
            name="NODE_02"
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
