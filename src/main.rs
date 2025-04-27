pub mod draw;
pub mod networking;
pub mod state;

use std::os::linux::raw::stat;

use clap::{Arg, Parser};
use crossterm::terminal::disable_raw_mode;
use draw::InputEvent;
use networking::{ExitResult, PlayerCommand, PlayerMessage};

#[derive(Parser)]
pub struct Args {
    #[arg(default_value = "postgresql://postgres:password@localhost:5432")]
    server_addr: String,
    #[arg(short)]
    name: String,
    #[arg(short)]
    password: String,
}

fn main() {
    let args = Args::parse();

    let server_conn = networking::ServerConnection::new(
        args.server_addr.clone(),
        args.name.clone(),
        args.password.clone(),
    );

    let mut drawer = draw::Drawer::new();
    let mut exit_result = None;
    'gameloop: loop {
        std::thread::sleep(std::time::Duration::from_millis(10));
        if server_conn.join_handle.is_finished() {
            exit_result = Some(server_conn.join_handle.join().unwrap());
            break 'gameloop;
        }
        let state = server_conn.last_state.load();
        let actions = drawer.fetch_events(&state);
        let Some(self_entity_id) = state.self_entity_id else {
            continue;
        };
        for a in actions {
            match a {
                InputEvent::Quit => {
                    break 'gameloop;
                }
                InputEvent::Attack(entity_id) => {
                    server_conn.create_commmand(PlayerCommand {
                        entity_id: self_entity_id,
                        command_type: "attack".to_owned(),
                        x: None,
                        y: None,
                        command_target: Some(entity_id),
                    });
                }
                InputEvent::Move((x, y)) => {
                    server_conn.create_commmand(PlayerCommand {
                        entity_id: self_entity_id,
                        command_type: "move".to_owned(),
                        x: Some(x),
                        y: Some(y),
                        command_target: None,
                    });
                }
                InputEvent::Pickup(entity_id) => {
                    server_conn.create_commmand(PlayerCommand {
                        entity_id: self_entity_id,
                        command_type: "pickup".to_owned(),
                        x: None,
                        y: None,
                        command_target: Some(entity_id),
                    });
                }
                InputEvent::Travel(entity_id) => {
                    server_conn.create_commmand(PlayerCommand {
                        entity_id: self_entity_id,
                        command_type: "travel".to_owned(),
                        x: None,
                        y: None,
                        command_target: Some(entity_id),
                    });
                }
                InputEvent::Say(text) => {
                    let (recipient, message) = text.split_once(" ").unwrap();
                    let msg = PlayerMessage {
                        speaker: self_entity_id,
                        recipient_species: recipient.to_owned(),
                        message: message.to_owned(),
                    };
                    server_conn.say(msg);
                }
            }
        }
        let state = server_conn.last_state.load();
        drawer.draw(&state);
    }

    drop(drawer);

    match exit_result {
        Some(ExitResult::LoginFailed) => {
            eprintln!("Login failed!");
        }
        _ => {}
    }
}
