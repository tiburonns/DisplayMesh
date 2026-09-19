use displaymesh_core::{
    Codec, ConnectionMedium, DisplayMode, DisplayPreset, NativeBackendStatus, NativeProofLevel,
    OperatingSystem, PeerCapabilities, Role, SessionConfig, SessionPhase, WireProtocol,
};
use eframe::egui;
use sys_locale::get_locale;

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AppLanguage {
    System,
    English,
    Spanish,
}

impl AppLanguage {
    const STORAGE_KEY: &'static str = "displaymesh.language";

    const fn as_key(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::English => "english",
            Self::Spanish => "spanish",
        }
    }

    fn from_key(value: &str) -> Option<Self> {
        match value {
            "system" => Some(Self::System),
            "english" => Some(Self::English),
            "spanish" => Some(Self::Spanish),
            _ => None,
        }
    }

    fn effective(self) -> EffectiveLanguage {
        match self {
            Self::English => EffectiveLanguage::English,
            Self::Spanish => EffectiveLanguage::Spanish,
            Self::System => {
                let locale = get_locale().unwrap_or_default().to_ascii_lowercase();
                if locale.starts_with("es") {
                    EffectiveLanguage::Spanish
                } else {
                    EffectiveLanguage::English
                }
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EffectiveLanguage {
    English,
    Spanish,
}

struct DisplayMeshApp {
    config: SessionConfig,
    phase: SessionPhase,
    preset_index: usize,
    message: String,
    language: AppLanguage,
}

impl DisplayMeshApp {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        cc.egui_ctx.set_visuals(egui::Visuals::dark());

        let language = cc
            .storage
            .and_then(|storage| storage.get_string(AppLanguage::STORAGE_KEY))
            .as_deref()
            .and_then(AppLanguage::from_key)
            .unwrap_or(AppLanguage::System);

        let mut app = Self {
            config: SessionConfig::default(),
            phase: SessionPhase::Idle,
            preset_index: 1,
            message: String::new(),
            language,
        };
        app.message = app.tr(
            "Native display backend not connected yet.",
            "El backend nativo de pantalla todavía no está conectado.",
        );
        app
    }

    fn tr(&self, english: &str, spanish: &str) -> String {
        match self.language.effective() {
            EffectiveLanguage::English => english.to_owned(),
            EffectiveLanguage::Spanish => spanish.to_owned(),
        }
    }

    fn backend_summary(&self) -> String {
        let status = NativeBackendStatus::current_development();

        let proof = match status.proof_level {
            NativeProofLevel::VirtualDisplayHarness => self.tr(
                "macOS virtual-display proof harness is available.",
                "El harness de prueba de pantalla virtual de macOS está disponible.",
            ),
            NativeProofLevel::DriverBootstrap => self.tr(
                "Windows software-device bootstrap is available; the IddCx driver is not integrated yet.",
                "El bootstrap de software device de Windows está disponible; el driver IddCx todavía no está integrado.",
            ),
            NativeProofLevel::None => self.tr(
                "No native display proof is available on this platform.",
                "No existe una prueba nativa de pantalla para esta plataforma.",
            ),
        };

        if status.can_start_real_session() {
            self.tr(
                &format!("{proof} Native backend is connected to the control app."),
                &format!("{proof} El backend nativo está conectado a la app de control."),
            )
        } else {
            self.tr(
                &format!("{proof} It is not connected to the control app yet, so real display sessions remain disabled."),
                &format!("{proof} Todavía no está conectado a la app de control, por lo que las sesiones reales siguen deshabilitadas."),
            )
        }
    }

    fn phase_label(&self) -> String {
        match (self.language.effective(), self.phase) {
            (EffectiveLanguage::English, SessionPhase::Idle) => "Idle",
            (EffectiveLanguage::English, SessionPhase::Discovering) => "Discovering",
            (EffectiveLanguage::English, SessionPhase::Pairing) => "Pairing",
            (EffectiveLanguage::English, SessionPhase::Connecting) => "Connecting",
            (EffectiveLanguage::English, SessionPhase::Streaming) => "Streaming",
            (EffectiveLanguage::English, SessionPhase::Stopping) => "Stopping",
            (EffectiveLanguage::English, SessionPhase::Failed) => "Failed",
            (EffectiveLanguage::Spanish, SessionPhase::Idle) => "Inactivo",
            (EffectiveLanguage::Spanish, SessionPhase::Discovering) => "Buscando",
            (EffectiveLanguage::Spanish, SessionPhase::Pairing) => "Emparejando",
            (EffectiveLanguage::Spanish, SessionPhase::Connecting) => "Conectando",
            (EffectiveLanguage::Spanish, SessionPhase::Streaming) => "Transmitiendo",
            (EffectiveLanguage::Spanish, SessionPhase::Stopping) => "Deteniendo",
            (EffectiveLanguage::Spanish, SessionPhase::Failed) => "Error",
        }
        .to_owned()
    }

    fn validate_development_session(&mut self) {
        let local = PeerCapabilities::development_scaffold();
        let remote = PeerCapabilities::development_scaffold();

        match self.config.negotiate(&local, &remote) {
            Ok(session) => {
                self.phase = SessionPhase::Idle;
                self.message = match OperatingSystem::current() {
                    OperatingSystem::MacOS => self.tr(
                        &format!(
                            "Configuration is compatible with the current development scaffold: {} / {} / {} / {}x{}@{} / {} Mbps. The macOS native backend still has to be connected before a real session can start.",
                            session.connection_medium,
                            session.wire_protocol,
                            session.codec,
                            session.preset.width,
                            session.preset.height,
                            session.preset.refresh_hz,
                            session.bitrate_mbps
                        ),
                        &format!(
                            "La configuración es compatible con el scaffold actual de desarrollo: {} / {} / {} / {}x{}@{} / {} Mbps. El backend nativo de macOS todavía debe conectarse antes de iniciar una sesión real.",
                            session.connection_medium,
                            session.wire_protocol,
                            session.codec,
                            session.preset.width,
                            session.preset.height,
                            session.preset.refresh_hz,
                            session.bitrate_mbps
                        ),
                    ),
                    OperatingSystem::Windows => self.tr(
                        &format!(
                            "Configuration is compatible with the current development scaffold: {} / {} / {} / {}x{}@{} / {} Mbps. The Windows IddCx backend still has to be connected before a real session can start.",
                            session.connection_medium,
                            session.wire_protocol,
                            session.codec,
                            session.preset.width,
                            session.preset.height,
                            session.preset.refresh_hz,
                            session.bitrate_mbps
                        ),
                        &format!(
                            "La configuración es compatible con el scaffold actual de desarrollo: {} / {} / {} / {}x{}@{} / {} Mbps. El backend IddCx de Windows todavía debe conectarse antes de iniciar una sesión real.",
                            session.connection_medium,
                            session.wire_protocol,
                            session.codec,
                            session.preset.width,
                            session.preset.height,
                            session.preset.refresh_hz,
                            session.bitrate_mbps
                        ),
                    ),
                    OperatingSystem::Unknown => self.tr(
                        "DisplayMesh currently targets macOS and Windows.",
                        "DisplayMesh actualmente está dirigido a macOS y Windows.",
                    ),
                };
            }
            Err(error) => {
                self.phase = SessionPhase::Failed;
                self.message = self.tr(
                    &format!("Unsupported development configuration: {error}"),
                    &format!("Configuración de desarrollo no soportada: {error}"),
                );
            }
        }
    }

    fn reset(&mut self) {
        self.config = SessionConfig::default();
        self.preset_index = 1;
        self.phase = SessionPhase::Idle;
        self.message = self.tr(
            "Native display backend not connected yet.",
            "El backend nativo de pantalla todavía no está conectado.",
        );
    }

    fn language_selector(&mut self, ui: &mut egui::Ui) {
        let current = match self.language {
            AppLanguage::System => self.tr("System", "Sistema"),
            AppLanguage::English => "English".to_owned(),
            AppLanguage::Spanish => "Español".to_owned(),
        };

        egui::ComboBox::from_id_salt("language")
            .selected_text(current)
            .show_ui(ui, |ui| {
                let system_label = self.tr("System", "Sistema");
                ui.selectable_value(&mut self.language, AppLanguage::System, system_label);
                ui.selectable_value(&mut self.language, AppLanguage::English, "English");
                ui.selectable_value(&mut self.language, AppLanguage::Spanish, "Español");
            });
    }
}

impl eframe::App for DisplayMeshApp {
    fn save(&mut self, storage: &mut dyn eframe::Storage) {
        storage.set_string(
            AppLanguage::STORAGE_KEY,
            self.language.as_key().to_owned(),
        );
    }

    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::TopBottomPanel::top("top").show(ctx, |ui| {
            ui.add_space(10.0);
            ui.horizontal(|ui| {
                ui.heading("DisplayMesh");
                ui.separator();
                ui.label(format!(
                    "{} {}",
                    self.tr("Running on", "Ejecutándose en"),
                    OperatingSystem::current()
                ));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    self.language_selector(ui);
                    ui.separator();
                    ui.label(self.phase_label());
                });
            });
            ui.add_space(8.0);
        });

        egui::SidePanel::left("navigation")
            .resizable(false)
            .default_width(210.0)
            .show(ctx, |ui| {
                let session_label = self.tr("Session", "Sesión");
                let share_label =
                    self.tr("Share this computer", "Compartir esta computadora");
                let receive_label =
                    self.tr("Use as remote display", "Usar como pantalla remota");

                ui.heading(session_label);
                ui.add_space(8.0);
                ui.selectable_value(&mut self.config.role, Role::Host, share_label);
                ui.selectable_value(
                    &mut self.config.role,
                    Role::Receiver,
                    receive_label,
                );

                ui.add_space(22.0);
                ui.heading(self.tr("Planned", "Planeado"));
                ui.add_space(8.0);
                ui.label(self.tr("Nearby devices", "Dispositivos cercanos"));
                ui.label(self.tr("Pairing", "Emparejamiento"));
                ui.label(self.tr("Input", "Entrada"));
                ui.label(self.tr("Statistics", "Estadísticas"));
                ui.label(self.tr("Settings", "Ajustes"));
            });

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading(match self.config.role {
                Role::Host => self.tr("Create a display session", "Crear una sesión de pantalla"),
                Role::Receiver => {
                    self.tr("Receive a display session", "Recibir una sesión de pantalla")
                }
            });
            ui.label(self.tr(
                "Shared control foundation for the macOS and Windows native backends.",
                "Base de control compartida para los backends nativos de macOS y Windows.",
            ));
            ui.label(self.tr(
                "USB and Wi-Fi are first-class connection modes. iPhone/iPad receivers are designed for native Retina resolution and touch/stylus input.",
                "USB y Wi-Fi son modos de conexión de primera clase. Los receptores iPhone/iPad están diseñados para resolución Retina nativa y entrada táctil/stylus.",
            ));
            ui.label(self.tr(
                "Only combinations supported by the current development capability scaffold can validate successfully.",
                "Sólo las combinaciones soportadas por las capacidades actuales de desarrollo pueden validarse correctamente.",
            ));
            ui.add_space(18.0);

            egui::Grid::new("session_config")
                .num_columns(2)
                .spacing([28.0, 14.0])
                .show(ui, |ui| {
                    let mode_label = self.tr("Mode", "Modo");
                    let extend_label = self.tr("Extend", "Extender");
                    let mirror_label = self.tr("Mirror", "Duplicar");
                    ui.label(mode_label);
                    ui.horizontal(|ui| {
                        ui.selectable_value(
                            &mut self.config.mode,
                            DisplayMode::Extend,
                            extend_label,
                        );
                        ui.selectable_value(
                            &mut self.config.mode,
                            DisplayMode::Mirror,
                            mirror_label,
                        );
                    });
                    ui.end_row();

                    ui.label(self.tr("Resolution", "Resolución"));
                    egui::ComboBox::from_id_salt("preset")
                        .selected_text(DisplayPreset::PRESETS[self.preset_index].name)
                        .show_ui(ui, |ui| {
                            for (index, preset) in DisplayPreset::PRESETS.iter().enumerate() {
                                let supported =
                                    PeerCapabilities::development_scaffold().supports_preset(*preset);
                                ui.add_enabled_ui(supported, |ui| {
                                    if ui
                                        .selectable_value(
                                            &mut self.preset_index,
                                            index,
                                            preset.name,
                                        )
                                        .clicked()
                                    {
                                        self.config.preset = *preset;
                                    }
                                });
                            }
                        });
                    ui.end_row();

                    ui.label(self.tr("Codec", "Códec"));
                    egui::ComboBox::from_id_salt("codec")
                        .selected_text(self.config.codec.to_string())
                        .show_ui(ui, |ui| {
                            let capabilities = PeerCapabilities::development_scaffold();
                            for codec in [Codec::H264, Codec::Hevc, Codec::Av1] {
                                ui.add_enabled_ui(capabilities.supports_codec(codec), |ui| {
                                    ui.selectable_value(
                                        &mut self.config.codec,
                                        codec,
                                        codec.to_string(),
                                    );
                                });
                            }
                        });
                    ui.end_row();

                    ui.label(self.tr("Connection", "Conexión"));
                    egui::ComboBox::from_id_salt("connection_medium")
                        .selected_text(self.config.connection_medium.to_string())
                        .show_ui(ui, |ui| {
                            let capabilities = PeerCapabilities::development_scaffold();
                            for medium in [
                                ConnectionMedium::Wifi,
                                ConnectionMedium::Usb,
                                ConnectionMedium::Ethernet,
                            ] {
                                ui.add_enabled_ui(
                                    capabilities.supports_connection_medium(medium),
                                    |ui| {
                                        ui.selectable_value(
                                            &mut self.config.connection_medium,
                                            medium,
                                            medium.to_string(),
                                        );
                                    },
                                );
                            }
                        });
                    ui.end_row();

                    ui.label(self.tr("Wire protocol", "Protocolo"));
                    egui::ComboBox::from_id_salt("wire_protocol")
                        .selected_text(self.config.wire_protocol.to_string())
                        .show_ui(ui, |ui| {
                            let capabilities = PeerCapabilities::development_scaffold();
                            for protocol in [WireProtocol::Quic, WireProtocol::Tcp] {
                                ui.add_enabled_ui(
                                    capabilities.supports_wire_protocol(protocol),
                                    |ui| {
                                        ui.selectable_value(
                                            &mut self.config.wire_protocol,
                                            protocol,
                                            protocol.to_string(),
                                        );
                                    },
                                );
                            }
                        });
                    ui.end_row();

                    ui.label(self.tr("Bitrate", "Bitrate"));
                    ui.horizontal(|ui| {
                        ui.add(
                            egui::Slider::new(&mut self.config.bitrate_mbps, 4..=100)
                                .suffix(" Mbps"),
                        );
                    });
                    ui.end_row();

                    let security_label = self.tr("Security", "Seguridad");
                    let encryption_label = self.tr(
                        "Require encrypted pairing",
                        "Requerir emparejamiento cifrado",
                    );
                    ui.label(security_label);
                    ui.checkbox(
                        &mut self.config.encryption_required,
                        encryption_label,
                    );
                    ui.end_row();
                });

            ui.add_space(24.0);
            ui.separator();
            ui.add_space(18.0);

            ui.horizontal(|ui| {
                if ui
                    .add_sized(
                        [190.0, 38.0],
                        egui::Button::new(self.tr(
                            "Validate configuration",
                            "Validar configuración",
                        )),
                    )
                    .clicked()
                {
                    self.validate_development_session();
                }

                if ui.button(self.tr("Reset", "Restablecer")).clicked() {
                    self.reset();
                }
            });

            ui.add_space(16.0);
            ui.group(|ui| {
                ui.label(self.tr("Backend status", "Estado del backend"));
                ui.label(self.backend_summary());
                ui.add_space(6.0);
                ui.monospace(&self.message);
            });
        });
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_english_language_is_deterministic() {
        assert_eq!(
            AppLanguage::English.effective(),
            EffectiveLanguage::English
        );
    }

    #[test]
    fn explicit_spanish_language_is_deterministic() {
        assert_eq!(
            AppLanguage::Spanish.effective(),
            EffectiveLanguage::Spanish
        );
    }

    #[test]
    fn language_storage_keys_round_trip() {
        for language in [
            AppLanguage::System,
            AppLanguage::English,
            AppLanguage::Spanish,
        ] {
            assert_eq!(
                AppLanguage::from_key(language.as_key()),
                Some(language)
            );
        }
        assert_eq!(AppLanguage::from_key("unknown"), None);
    }
}
