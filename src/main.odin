package main
import rl "vendor/raylib"
import "core:math"
import "core:strconv"
import "core:strings"

main::proc()
{
    rl.InitWindow(2048, 1024, "raylib [core] example - basic window")
    rl.SetWindowState({.WINDOW_TRANSPARENT})

    texture := rl.LoadTexture("resources/DaxodeProfile.png");

    winResizeAmount : i32 = 0
    someString := make([]byte,32)

    for !rl.WindowShouldClose() {
        if (rl.IsKeyDown(.SPACE)) {
            q := strings.concatenate({"Amount of times resized: ", strconv.itoa(someString, int(winResizeAmount))}, context.temp_allocator)
            rl.SetWindowTitle(strings.clone_to_cstring(q))
            winResizeAmount += 1
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{0,0,0,0})
        
        rød_grød_med_fløde : cstring = "Congrats! You created your first window!";
        rl.DrawText(rød_grød_med_fløde, rl.MeasureText(rød_grød_med_fløde, rl.GetScreenHeight()>>4)>>2, i32(100*(0.5+0.5*math.sin(f32(rl.GetTime()*math.π)))), rl.GetScreenHeight()>>4, rl.RED)
        //rl.DrawFPS(0,0);

        widthTex := f32(texture.width)*0.5

        // rl.DrawTextureEx(texture, 
        //     {f32(rl.GetScreenWidth())*0.5-widthTex*0.5, rl.EaseSineInOut(f32(rl.GetTime()), 0, f32(rl.GetScreenHeight())-widthTex, 2)},
        //     0, 0.5, rl.WHITE)

        rl.EndDrawing()
    }

    rl.CloseWindow()
}