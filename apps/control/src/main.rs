use displaymesh_core::{
    Codec, DisplayMode, DisplayPreset, OperatingSystem, Role, SessionConfig, SessionPhase,
    Transport,
};
use eframe::egui;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([980.0, 680.0])
            .with_min_inner_size([760.0, 560.0])
            .with_title("DisplayMesh"),
        ..Default::default()
    };

    eframe::run_native(
        "DisplayMesh",
        options,
        Box::new(|cc| Ok(Box::new(DisplayMeshApp::new(cc)))),
    )
}

struct DisplayMeshApp {
    config: SessionConfig,
    phase: SessionPhase,
    preset_index: usize,
    message: String,
}

impl DisplayMeshApp {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        cc.egui_ctx.set_visuals(egui::Visuals::dark());

        Self {
            config: SessionConfig::default(),
            phase: SessionPhase::Idle,
            preset_index: 1,
            message: "Native display backend not connected yet.".to_owned(),
        }
    }

    fn start(&mut self) {
        match self.config.validate() {
            Ok(()) => {
                self.phase = SessionPhase::Connecting;
                self.message = match OperatingSystem::current() {
                    OperatingSystem::MacOS => {
                        "Configuration is valid. Waiting for the macOS virtual-display backend."
                    }
                    OperatingSystem::Windows => {
                        "Configuration is valid. Waiting for the Windows IddCx backend."
                    }
                    OperatingSystem::Unknown => "DisplayMesh currently targets macOS and Windows.",
                }
                .to_owned();
            }
            Err(error) => {
                self.phase = SessionPhase::Failed;
                self.message = error.to_string();
            }
        }
    }
}

impl eframe::App for DisplayMeshApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::TopBottomPanel::top("top").show(ctx, |ui| {
            ui.add_space(10.0);
            ui.horizontal(|ui| {
                ui.heading("DisplayMesh");
                ui.separator();
                ui.label(format!("Running on {}", OperatingSystem::current()));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(self.phase.label());
                });
            });
            ui.add_space(8.0);
        });

        egui::SidePanel::left("navigation")
            .resizable(false)
            .default_width(210.0)
            .show(ctx, |ui| {
                ui.heading("Session");
                ui.add_space(8.0);
                ui.selectable_value(&mut self.config.role, Role::Host, "Share this computer");
                ui.selectable_value(
                    &mut self.config.role,
                    Role::Receiver,
                    "Use as remote display",
                );

                ui.add_space(22.0);
                ui.heading("Planned");
                ui.add_space(8.0);
                ui.label("Nearby devices");
                ui.label("Pairing");
                ui.label("Input");
                ui.label("Statistics");
                ui.label("Settings");
            });

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading(match self.config.role {
                Role::Host => "Create a display session",
                Role::Receiver => "Receive a display session",
            });
            ui.label("Shared UI foundation for the macOS and Windows native backends.");
            ui.add_space(18.0);

            egui::Grid::new("session_config")
                .num_columns(2)
                .spacing([28.0, 14.0])
                .show(ui, |ui| {
                    ui.label("Mode");
                    ui.horizontal(|ui| {
                        ui.selectable_value(&mut self.config.mode, DisplayMode::Extend, "Extend");
                        ui.selectable_value(&mut self.config.mode, DisplayMode::Mirror, "Mirror");
                    });
                    ui.end_row();

                    ui.label("Resolution");
                    egui::ComboBox::from_id_salt("preset")
                        .selected_text(DisplayPreset::PRESETS[self.preset_index].name)
                        .show_ui(ui, |ui| {
                            for (index, preset) in DisplayPreset::PRESETS.iter().enumerate() {
                                if ui
                                    .selectable_value(&mut self.preset_index, index, preset.name)
                                    .clicked()
                                {
                                    self.config.preset = *preset;
                                }
                            }
                        });
                    ui.end_row();

                    ui.label("Codec");
                    egui::ComboBox::from_id_salt("codec")
                        .selected_text(self.config.codec.to_string())
                        .show_ui(ui, |ui| {
                            ui.selectable_value(&mut self.config.codec, Codec::H264, "H.264");
                            ui.selectable_value(&mut self.config.codec, Codec::Hevc, "HEVC");
                            ui.selectable_value(&mut self.config.codec, Codec::Av1, "AV1");
                        });
                    ui.end_row();

                    ui.label("Transport");
                    egui::ComboBox::from_id_salt("transport")
                        .selected_text(self.config.transport.to_string())
                        .show_ui(ui, |ui| {
                            ui.selectable_value(
                                &mut self.config.transport,
                                Transport::Quic,
                                "QUIC",
                            );
                            ui.selectable_value(&mut self.config.transport, Transport::Tcp, "TCP");
                            ui.selectable_value(&mut self.config.transport, Transport::Usb, "USB");
                        });
                    ui.end_row();

                    ui.label("Bitrate");
                    ui.horizontal(|ui| {
                        ui.add(
                            egui::Slider::new(&mut self.config.bitrate_mbps, 4..=100)
                                .suffix(" Mbps"),
                        );
                    });
                    ui.end_row();

                    ui.label("Security");
                    ui.checkbox(
                        &mut self.config.encryption_required,
                        "Require encrypted pairing",
                    );
                    ui.end_row();
                });

            ui.add_space(24.0);
            ui.separator();
            ui.add_space(18.0);

            ui.horizontal(|ui| {
                if ui
                    .add_sized([160.0, 38.0], egui::Button::new("Start session"))
                    .clicked()
                {
                    self.start();
                }

                if ui.button("Reset").clicked() {
                    self.config = SessionConfig::default();
                    self.preset_index = 1;
                    self.phase = SessionPhase::Idle;
                    self.message = "Native display backend not connected yet.".to_owned();
                }
            });

            ui.add_space(16.0);
            ui.group(|ui| {
                ui.label("Backend status");
                ui.monospace(&self.message);
            });
        });
    }
}
