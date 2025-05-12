use std::time::{SystemTime, UNIX_EPOCH};

use tauri::{
    menu::{Menu, MenuBuilder, MenuItem, MenuItemBuilder, SubmenuBuilder},
    App, AppHandle, Manager, WebviewUrl, WebviewWindowBuilder, Wry,
};

fn create_new_window_menu_item(app: &App) -> MenuItem<Wry> {
    MenuItemBuilder::new("New Window")
        .accelerator("CmdOrCtrl+n")
        .id("new_window")
        .build(app)
        .unwrap()
}

fn create_file_menu(app: &App) -> Menu<Wry> {
    let new_window_item =
        MenuItem::with_id(app, "new_window", "New Window", true, Some("Ctrl+N")).unwrap();

    let file_menu = SubmenuBuilder::new(app, "File")
        .items(&[&new_window_item])
        .build()
        .unwrap();

    MenuBuilder::new(app).items(&[&file_menu]).build().unwrap()
}

fn create_main_window(app: &AppHandle) {
    let mut main_window_cfg = app
        .config()
        .app
        .windows
        .iter()
        .find(|w| w.label == "main")
        .expect("no main window in config")
        .clone();
    let label = format!(
        "main{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
    );

    main_window_cfg.label = label;
    if tauri::is_dev() {
        main_window_cfg.url = WebviewUrl::External(app.config().build.dev_url.clone().unwrap());
    }

    WebviewWindowBuilder::from_config(app, &main_window_cfg)
        .expect("failed to create builder")
        .build()
        .expect("failed to build window");
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

            let main_window = app.get_webview_window("main").unwrap();
            if let Some(menu) = main_window.menu() {
                let file_menu = menu
                    .items()
                    .unwrap()
                    .iter()
                    .map(|submenu| submenu.as_submenu().unwrap())
                    .find(|sub| sub.text().ok() == Some("File".to_string()))
                    .unwrap()
                    .clone();
                let new_window_item = create_new_window_menu_item(app);
                file_menu.insert(&new_window_item, 0)?;
                app.set_menu(menu)?;

                app.on_menu_event(|app, e| {
                    if e.id() == "new_window" {
                        create_main_window(app);
                    }
                });
                Ok(())
            } else {
                let menu = create_file_menu(app);
                let _ = main_window.set_menu(menu.clone());
                main_window.on_menu_event(move |win, e| {
                    if e.id() == "new_window" {
                        create_main_window(win.app_handle());
                    }
                });
                Ok(())
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
