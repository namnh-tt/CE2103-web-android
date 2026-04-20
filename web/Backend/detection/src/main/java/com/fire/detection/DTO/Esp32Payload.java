package com.fire.detection.DTO;

import lombok.Data;

@Data
public class Esp32Payload {
    private String node_id;
    private double temperature;
    private String fire_status;
    private String device_status;

}
