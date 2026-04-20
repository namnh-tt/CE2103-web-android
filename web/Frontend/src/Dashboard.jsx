import React, { useEffect, useState } from "react";
import axios from "axios";

const API = "https://fire-backend-275g.onrender.com/api/fire-data/status";

const getStatusColor = (status) => {
  switch (status) {
    case "FIRE":
      return "#ff4d4f";
    case "NORMAL":
      return "#52c41a";
    case "OFFLINE":
      return "#595959";
    default:
      return "#1890ff";
  }
};

// 🔥 Format time đẹp
const formatTime = (timeStr) => {
  const date = new Date(timeStr);
  return date.toLocaleString("vi-VN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    day: "2-digit",
    month: "2-digit",
  });
};

// 🔥 Decode sensor status
const getSensorStatus = (deviceStatus) => {
  switch (deviceStatus) {
    case "0":
      return {
        s1: "Hoạt động",
        s2: "Hoạt động",
        color1: "#52c41a",
        color2: "#52c41a",
      };
    case "1":
      return {
        s1: "Lỗi",
        s2: "Hoạt động",
        color1: "#ff4d4f",
        color2: "#52c41a",
      };
    case "2":
      return {
        s1: "Hoạt động",
        s2: "Lỗi",
        color1: "#52c41a",
        color2: "#ff4d4f",
      };
    default:
      return {
        s1: "Không rõ",
        s2: "Không rõ",
        color1: "#999",
        color2: "#999",
      };
  }
};

export default function Dashboard() {
  const [data, setData] = useState([]);

  const fetchData = async () => {
    try {
      const res = await axios.get(API);
      setData(res.data);
    } catch (err) {
      console.error("Error fetch data:", err);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div style={{ padding: 20 }}>
      {" "}
      <h1>🔥 Fire Monitoring Admin</h1>
      ```
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))",
          gap: 16,
        }}
      >
        {data.map((item) => {
          const sensor = getSensorStatus(item.deviceStatus);

          return (
            <div
              key={item.id}
              style={{
                borderRadius: 10,
                padding: 16,
                background: "#1f1f1f",
                color: "white",
                borderLeft: `6px solid ${getStatusColor(item.status)}`,
                boxShadow: "0 2px 8px rgba(0,0,0,0.3)",
              }}
            >
              <h3>
                {item.deviceId} - {item.sensorId}
              </h3>

              <p>📍 {item.location}</p>
              <p>🌡 Temp: {item.temperature} °C</p>

              <p>
                Status:{" "}
                <b style={{ color: getStatusColor(item.status) }}>
                  {item.status}
                </b>
              </p>

              {/* 🔥 SENSOR STATUS */}
              <div style={{ marginTop: 10 }}>
                <p>
                  Sensor 1: <b style={{ color: sensor.color1 }}>{sensor.s1}</b>
                </p>
                <p>
                  Sensor 2: <b style={{ color: sensor.color2 }}>{sensor.s2}</b>
                </p>
              </div>

              {/* 🔥 TIME FORMAT */}
              <p style={{ fontSize: 12, opacity: 0.7 }}>
                ⏱ {formatTime(item.lastUpdated)}
              </p>
            </div>
          );
        })}
      </div>
    </div>
  );
}
