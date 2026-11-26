//! Handle annotations: one resource read two ways (a float load and an
//! integer atomic) gets an annotation of each element type (#177, #2723).
//! Kept out of `lower.rs`, which is at the asset policy's size limit.

use super::lower::{Parts, lower};
use crate::native::{
    ComputeIo, HwStage, NativeProgram, ResourceType, RootParam, RootType, StageIo, UsedResource,
};
use crate::{io, ir, resource, structure};

const S_ENDPGM: u32 = 0xBF81_0000;

/// MIMG `op vdata, v[vaddr..], s[srsrc..srsrc+7]` on a 2D image.
const fn mimg_2d(op: u8, dmask: u8, vdata: u8, vaddr: u8, srsrc: u8) -> [u32; 2] {
    [
        0x3C << 26 | (op as u32 & 0x7F) << 18 | (dmask as u32) << 8 | 1 << 3,
        ((srsrc as u32 >> 2) & 0x1F) << 16 | (vdata as u32) << 8 | vaddr as u32,
    ]
}

#[test]
fn an_image_read_as_float_and_by_an_atomic_is_annotated_twice() {
    // One 2D image UAV from the descriptor table at s4, loaded (four
    // float channels) and then atomically minimised in the same block.
    let mut words = vec![
        0xBE85_0380, // s_mov_b32 s5, 0
        // s_load_dwordx8 s[8:15], s[4:5], 0
        0x3D << 26 | 0x03 << 18 | 8 << 6 | 4 >> 1,
        125 << 25,
        0x7E00_0280, // v_mov_b32 v0, 0
        0x7E02_0280, // v_mov_b32 v1, 0
    ];
    words.extend(mimg_2d(0x00, 0xF, 2, 0, 8)); // image_load v[2:5], v[0:1], s[8:15]
    words.extend(mimg_2d(0x15, 0x1, 2, 0, 8)); // image_atomic_umin v2, v[0:1], s[8:15]
    words.push(S_ENDPGM);
    let code: Vec<u8> = words.iter().flat_map(|w| w.to_le_bytes()).collect();
    let native = NativeProgram {
        stage: HwStage::Cs,
        wave64: false,
        vgprs: 8,
        layout: vec![RootParam {
            root: RootType::Table,
            table_offset_dwords: 0,
            sgprs: 1,
            base_register: 0,
            user_data: 4,
            slot: 0,
        }],
        used: vec![UsedResource {
            kind: ResourceType::Uav,
            root: RootType::Table,
            table_offset_dwords: 0,
            lower_bound: 0,
            stride: 0,
            dwords: 8,
            user_data: 4,
            slot: 0,
        }],
        io: StageIo::Cs(ComputeIo {
            rsrc2: 5 << 1, // 5 user SGPRs: s0..s4
            threads: [1, 1, 1],
        }),
        code,
    };
    let p = ir::build(&native.code, false, native.vgprs).unwrap();
    let res = resource::track(&p, &native.layout, native.stage, None).unwrap();
    let io = io::raise(&p, &native).unwrap();
    let st = structure::structure(&p).unwrap();
    let lowered = lower(&Parts {
        native: &native,
        p: &p,
        st: &st,
        io: &io,
        res: &res,
        inputs: vec![],
        outputs: vec![],
        prims: vec![],
        mesh_stride: 0,
        view_marks: false,
    })
    .unwrap();

    // DXIL resource properties: word 0 is the kind (Texture2D = 2) with
    // the UAV bit (0x1000); word 1 is the component type in the low byte
    // (U32 = 5, F32 = 9, DxilConstants.h `ComponentType`) and the
    // component count above it. D3D12 allows atomics (Interlocked*) on
    // integer UAVs only, so the atomic needs its own one-U32 annotation
    // next to the load's four-float one.
    const TEXTURE_2D_UAV: u32 = 0x1002;
    assert!(
        lowered.annotations.contains(&(TEXTURE_2D_UAV, 0x409)),
        "the load's annotation: {:x?}",
        lowered.annotations
    );
    assert!(
        lowered.annotations.contains(&(TEXTURE_2D_UAV, 0x105)),
        "the atomic's annotation: {:x?}",
        lowered.annotations
    );
}
