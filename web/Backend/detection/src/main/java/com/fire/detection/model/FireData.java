package com.fire.detection.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "fire_data")
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Getter
@Setter
public class FireData {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ESP32 nào gửi
    private String deviceId;

    // Sensor nào (ví dụ: S1, S2)
    private String sensorId;

    // Khu vực (phòng, tầng,...)
    private String location;

    // Nhiệt độ
    private double temperature;

    // Trạng thái: FIRE / NORMAL
    @Enumerated(EnumType.STRING)
    private EStatus status;

    // Thời gian nhận
    private LocalDateTime createdAt;

    @PrePersist
    public void prePersist() {
        this.createdAt = LocalDateTime.now();
    }
    private String deviceStatus; // "0", "1", "2"

}