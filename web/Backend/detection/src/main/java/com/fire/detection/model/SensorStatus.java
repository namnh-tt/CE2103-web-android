package com.fire.detection.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "sensor_status")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SensorStatus {

    @Id
    private String id;
    // format: deviceId_sensorId (vd: esp01_S1)

    private String deviceId;
    private String sensorId;

    private double temperature;

    @Enumerated(EnumType.STRING)
    private EStatus status;

    private String location;

    private LocalDateTime lastUpdated;
    private String deviceStatus; // "0", "1", "2"
}
