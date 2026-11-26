//! Loop shapes dxil-spirv converts: a latch branches back to one header
//! (dxil-spirv#380, #2977). Kept out of `lower.rs`, which is at the asset
//! policy's size limit.

use super::lower::{Lowered, Parts, lower};
use crate::native::{ComputeIo, HwStage, NativeProgram, StageIo};
use crate::{io, ir, resource, structure};

const S_ENDPGM: u32 = 0xBF81_0000;

/// Lowers a wave32 compute program with no root parameters, as
/// `lower.rs`'s `lower_with` does.
fn lower_empty(words: &[u32]) -> Result<Lowered, crate::ShaderError> {
    let code: Vec<u8> = words.iter().flat_map(|w| w.to_le_bytes()).collect();
    let native = NativeProgram {
        stage: HwStage::Cs,
        wave64: false,
        vgprs: 256,
        layout: vec![],
        used: vec![],
        io: StageIo::Cs(ComputeIo {
            // Two user SGPRs, 512 bytes of LDS.
            rsrc2: 1 << 15 | 2 << 1,
            threads: [1, 1, 1],
        }),
        code,
    };
    let p = ir::build(&native.code, false, 256).unwrap();
    let st = structure::structure(&p).unwrap();
    let res = resource::track(&p, &native.layout, native.stage, Some(&st))?;
    let io = io::raise(&p, &native).unwrap();
    lower(&Parts {
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
}

/// A latch that branches back to both its loop's header and the outer
/// loop's (the shape of a first-lane table offset loop) branches back to
/// one header only: the outer back edge leaves through a latch of its own
/// (dxil-spirv#380).
#[test]
fn a_latch_branches_back_to_one_header() {
    let words = [
        0xBE80_0380, // s_mov_b32 s0, 0
        0xBF82_0007, // s_branch outer
        0x8001_8101, // latch: s_add_u32 s1, s1, 1
        0xBF06_8301, // s_cmp_eq_u32 s1, 3
        0xBF85_0004, // s_cbranch_scc1 outer
        0x8000_8100, // inner: s_add_u32 s0, s0, 1
        0xBF06_8400, // s_cmp_eq_u32 s0, 4
        0xBF85_0003, // s_cbranch_scc1 end
        0xBF82_FFF9, // s_branch latch
        0xBE81_0380, // outer: s_mov_b32 s1, 0
        0xBF82_FFFA, // s_branch inner
        S_ENDPGM,    // end
    ];
    let l = lower_empty(&words).unwrap();
    let back = &l.back_edges;
    assert!(back.iter().all(|b| b.len() <= 1), "{back:?}");
    // Its own latch and the outer loop's.
    assert_eq!(back.iter().filter(|b| !b.is_empty()).count(), 2);
}
