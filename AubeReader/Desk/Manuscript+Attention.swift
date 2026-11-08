import Foundation

extension Manuscript {
  /// “Attention Is All You Need” (Vaswani et al., NIPS 2017, arXiv:1706.03762):
  /// everything around its paragraphs, which are in `Resources/attention.json`.
  static let attention = Manuscript(
    id: "attention",
    title: "Attention Is All You Need",
    abstract:
      "The dominant sequence transduction models are based on complex recurrent or convolutional neural networks that include an encoder and a decoder. The best performing models also connect the encoder and decoder through an attention mechanism. We propose a new simple network architecture, the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely. Experiments on two machine translation tasks show these models to be superior in quality while being more parallelizable and requiring significantly less time to train. Our model achieves 28.4 BLEU on the WMT 2014 English-to-German translation task, improving over the existing best results, including ensembles, by over 2 BLEU. On the WMT 2014 English-to-French translation task, our model establishes a new single-model state-of-the-art BLEU score of 41.8 after training for 3.5 days on eight GPUs, a small fraction of the training costs of the best models from the literature. We show that the Transformer generalizes well to other tasks by applying it successfully to English constituency parsing both with large and limited training data.",
    keywords: "Transformer · self-attention · multi-head attention · machine translation · sequence transduction",
    authors: [
      "Ashish Vaswani", "Noam Shazeer", "Niki Parmar", "Jakob Uszkoreit", "Llion Jones", "Aidan N. Gomez", "Łukasz Kaiser",
      "Illia Polosukhin",
    ],
    places: [1, 1, 2, 2, 2, 3, 1, 0],
    affiliations: [
      ("Google Brain", "Google Brain"),
      ("Google Research", "Google Research"),
      ("University of Toronto", "University of Toronto"),
    ],
    received: "(Submitted 12 June 2017; revised 6 December 2017; this version 2 August 2023)",
    preprint: "PREPRINT  ·  ARXIV:1706.03762  ·  NIPS 2017",
    journal: "ADVANCES IN NEURAL INFORMATION PROCESSING SYSTEMS **30**, 5998 (2017)",
    date: "DECEMBER 2017",
    doi: "DOI: 10.48550/arXiv.1706.03762",
    footer: ("31st Conference on Neural Information Processing Systems (NIPS 2017), Long Beach, CA, USA.", "arXiv:1706.03762v7"),
    sections: [
      Section(title: "Introduction", paragraphs: [0, 1, 2]),
      Section(title: "Background", paragraphs: [3, 4, 5]),
      Section(title: "Model Architecture", paragraphs: [6], within: [6: [.figure(.transformer)]]),
      Section(title: "Encoder and Decoder Stacks", level: 2, paragraphs: [7, 8]),
      Section(title: "Attention", level: 2, paragraphs: [9]),
      Section(
        title: "Scaled Dot-Product Attention", level: 3, paragraphs: [10, 11, 12], after: [.figure(.attention)],
        within: [10: [.equation(#"\mathrm{Attention}(Q, K, V) = \mathrm{softmax}\left(\frac{QK^T}{\sqrt{d_k}}\right)V"#)]]),
      Section(
        title: "Multi-Head Attention", level: 3, paragraphs: [13, 14],
        within: [
          13: [
            .equation(#"\mathrm{MultiHead}(Q, K, V) = \mathrm{Concat}(\mathrm{head}_1, \ldots, \mathrm{head}_h)W^O"#),
            .equation(#"\mathrm{head}_i = \mathrm{Attention}(QW^Q_i, KW^K_i, VW^V_i)"#),
          ]
        ]),
      Section(title: "Applications of Attention in our Model", level: 3, paragraphs: [15, 16, 17]),
      Section(
        title: "Position-wise Feed-Forward Networks", level: 2, paragraphs: [18],
        within: [18: [.equation(#"\mathrm{FFN}(x) = \max(0, xW_1 + b_1)W_2 + b_2"#)]]),
      Section(title: "Embeddings and Softmax", level: 2, paragraphs: [19]),
      Section(
        title: "Positional Encoding", level: 2, paragraphs: [20, 21],
        within: [
          20: [
            .equation(#"PE_{(pos,2i)} = \sin(pos/10000^{2i/d_{\mathrm{model}}})"#),
            .equation(#"PE_{(pos,2i+1)} = \cos(pos/10000^{2i/d_{\mathrm{model}}})"#),
          ]
        ]),
      Section(title: "Why Self-Attention", paragraphs: [22, 23, 24, 25, 26], within: [23: [.table(0)]]),
      Section(title: "Training"),
      Section(title: "Training Data and Batching", level: 2, paragraphs: [27]),
      Section(title: "Hardware and Schedule", level: 2, paragraphs: [28]),
      Section(
        title: "Optimizer", level: 2, paragraphs: [29],
        within: [
          29: [
            .equation(
              #"lrate = d_{\mathrm{model}}^{-0.5} \cdot \min(step\_num^{-0.5},\, step\_num \cdot warmup\_steps^{-1.5})"#)
          ]
        ]),
      Section(title: "Regularization", level: 2, paragraphs: [30]),
      Section(title: "Results"),
      Section(title: "Machine Translation", level: 2, paragraphs: [31, 32, 33, 34], within: [31: [.table(1)]]),
      Section(title: "Model Variations", level: 2, paragraphs: [35, 36, 37], within: [35: [.table(2)]]),
      Section(title: "English Constituency Parsing", level: 2, paragraphs: [38, 39, 40, 41], after: [.table(3)]),
      Section(title: "Conclusion", paragraphs: [42, 43]),
      Section(title: "Attention Visualizations", numbered: false, after: [.figure(.making), .figure(.anaphora)]),
    ],
    captions: [
      .transformer: "The Transformer – model architecture.",
      .attention: "(left) Scaled Dot-Product Attention. (right) Multi-Head Attention consists of several attention layers running in parallel.",
      .making:
        "An example of the attention mechanism following long-distance dependencies in the encoder self-attention in layer 5 of 6. Many of the attention heads attend to a distant dependency of the verb ‘making’, completing the phrase ‘making…more difficult’. Attentions here shown only for the word ‘making’. Different line styles represent different heads (redrawn schematically).",
      .anaphora:
        "Two attention heads, also in layer 5 of 6, apparently involved in anaphora resolution: isolated attentions from just the word ‘its’ for attention heads 5 and 6 (redrawn schematically). Note that the attentions are very sharp for this word.",
    ],
    tables: [
      Table(
        caption:
          "Maximum path lengths, per-layer complexity and minimum number of sequential operations for different layer types. *n* is the sequence length, *d* is the representation dimension, *k* is the kernel size of convolutions and *r* the size of the neighborhood in restricted self-attention.",
        header: ["Layer Type", "Complexity per Layer", "Sequential Operations", "Maximum Path Length"],
        rows: [
          ["Self-Attention", "*O*(*n*^{2} · *d*)", "*O*(1)", "*O*(1)"],
          ["Recurrent", "*O*(*n* · *d*^{2})", "*O*(*n*)", "*O*(*n*)"],
          ["Convolutional", "*O*(*k* · *n* · *d*^{2})", "*O*(1)", "*O*(log_{*k*}(*n*))"],
          ["Self-Attention (restricted)", "*O*(*r* · *n* · *d*)", "*O*(1)", "*O*(*n*/*r*)"],
        ],
        wide: true),
      Table(
        caption:
          "The Transformer achieves better BLEU scores than previous state-of-the-art models on the English-to-German and English-to-French newstest2014 tests at a fraction of the training cost.",
        header: ["Model", "EN-DE", "EN-FR", "EN-DE", "EN-FR"],
        rows: [
          ["ByteNet", "23.75", "", "", ""],
          ["Deep-Att + PosUnk", "", "39.2", "", "1.0 · 10^{20}"],
          ["GNMT + RL", "24.6", "39.92", "2.3 · 10^{19}", "1.4 · 10^{20}"],
          ["ConvS2S", "25.16", "40.46", "9.6 · 10^{18}", "1.5 · 10^{20}"],
          ["MoE", "26.03", "40.56", "2.0 · 10^{19}", "1.2 · 10^{20}"],
          ["Deep-Att + PosUnk Ensemble", "", "40.4", "", "8.0 · 10^{20}"],
          ["GNMT + RL Ensemble", "26.30", "41.16", "1.8 · 10^{20}", "1.1 · 10^{21}"],
          ["ConvS2S Ensemble", "26.36", "**41.29**", "7.7 · 10^{19}", "1.2 · 10^{21}"],
          ["Transformer (base model)", "27.3", "38.1", "**3.3 · 10^{18}**", "<"],
          ["Transformer (big)", "**28.4**", "**41.8**", "2.3 · 10^{19}", "<"],
        ],
        over: [("BLEU", 1, 2), ("Training Cost (FLOPs)", 3, 4)], breaks: [5, 8], wide: true),
      Table(
        caption:
          "Variations on the Transformer architecture. Unlisted values are identical to those of the base model. All metrics are on the English-to-German translation development set, newstest2013. Listed perplexities are per-wordpiece, according to our byte-pair encoding, and should not be compared to per-word perplexities.",
        header: [
          "", "*N*", "*d*_{model}", "*d*_{ff}", "*h*", "*d*_{k}", "*d*_{v}", "*P*_{drop}", "*ε*_{ls}", "train steps", "PPL (dev)",
          "BLEU (dev)", "params ×10^{6}",
        ],
        rows: [
          ["base", "6", "512", "2048", "8", "64", "64", "0.1", "0.1", "100K", "4.92", "25.8", "65"],
          ["(A)", "", "", "", "1", "512", "512", "", "", "", "5.29", "24.9", ""],
          ["", "", "", "", "4", "128", "128", "", "", "", "5.00", "25.5", ""],
          ["", "", "", "", "16", "32", "32", "", "", "", "4.91", "25.8", ""],
          ["", "", "", "", "32", "16", "16", "", "", "", "5.01", "25.4", ""],
          ["(B)", "", "", "", "", "16", "", "", "", "", "5.16", "25.1", "58"],
          ["", "", "", "", "", "32", "", "", "", "", "5.01", "25.4", "60"],
          ["(C)", "2", "", "", "", "", "", "", "", "", "6.11", "23.7", "36"],
          ["", "4", "", "", "", "", "", "", "", "", "5.19", "25.3", "50"],
          ["", "8", "", "", "", "", "", "", "", "", "4.88", "25.5", "80"],
          ["", "", "256", "", "", "32", "32", "", "", "", "5.75", "24.5", "28"],
          ["", "", "1024", "", "", "128", "128", "", "", "", "4.66", "26.0", "168"],
          ["", "", "", "1024", "", "", "", "", "", "", "5.12", "25.4", "53"],
          ["", "", "", "4096", "", "", "", "", "", "", "4.75", "26.2", "90"],
          ["(D)", "", "", "", "", "", "", "0.0", "", "", "5.77", "24.6", ""],
          ["", "", "", "", "", "", "", "0.2", "", "", "4.95", "25.5", ""],
          ["", "", "", "", "", "", "", "", "0.0", "", "4.67", "25.3", ""],
          ["", "", "", "", "", "", "", "", "0.2", "", "5.47", "25.7", ""],
          ["(E)", "", "positional embedding instead of sinusoids", "<", "<", "<", "<", "<", "<", "", "4.92", "25.7", ""],
          ["big", "6", "1024", "4096", "16", "", "", "0.3", "", "300K", "**4.33**", "**26.4**", "213"],
        ],
        breaks: [1, 5, 7, 14, 18, 19], wide: true),
      Table(
        caption: "The Transformer generalizes well to English constituency parsing (Results are on Section 23 of WSJ).",
        header: ["Parser", "Training", "WSJ 23 F1"],
        rows: [
          ["Vinyals & Kaiser et al. (2014)", "WSJ only, discriminative", "88.3"],
          ["Petrov et al. (2006)", "WSJ only, discriminative", "90.4"],
          ["Zhu et al. (2013)", "WSJ only, discriminative", "90.4"],
          ["Dyer et al. (2016)", "WSJ only, discriminative", "91.7"],
          ["Transformer (4 layers)", "WSJ only, discriminative", "91.3"],
          ["Zhu et al. (2013)", "semi-supervised", "91.3"],
          ["Huang & Harper (2009)", "semi-supervised", "91.3"],
          ["McClosky et al. (2006)", "semi-supervised", "92.1"],
          ["Vinyals & Kaiser et al. (2014)", "semi-supervised", "92.1"],
          ["Transformer (4 layers)", "semi-supervised", "92.7"],
          ["Luong et al. (2015)", "multi-task", "93.0"],
          ["Dyer et al. (2016)", "generative", "93.3"],
        ],
        breaks: [4, 5, 9, 10]),
    ],
    references: [
      "J. L. Ba, J. R. Kiros, and G. E. Hinton, Layer normalization, arXiv:1607.06450 (2016).",
      "D. Bahdanau, K. Cho, and Y. Bengio, Neural machine translation by jointly learning to align and translate, CoRR abs/1409.0473 (2014).",
      "D. Britz, A. Goldie, M.-T. Luong, and Q. V. Le, Massive exploration of neural machine translation architectures, CoRR abs/1703.03906 (2017).",
      "J. Cheng, L. Dong, and M. Lapata, Long short-term memory-networks for machine reading, arXiv:1601.06733 (2016).",
      "K. Cho, B. van Merrienboer, C. Gulcehre, F. Bougares, H. Schwenk, and Y. Bengio, Learning phrase representations using RNN encoder-decoder for statistical machine translation, CoRR abs/1406.1078 (2014).",
      "F. Chollet, Xception: Deep learning with depthwise separable convolutions, arXiv:1610.02357 (2016).",
      "J. Chung, Ç. Gülçehre, K. Cho, and Y. Bengio, Empirical evaluation of gated recurrent neural networks on sequence modeling, CoRR abs/1412.3555 (2014).",
      "C. Dyer, A. Kuncoro, M. Ballesteros, and N. A. Smith, Recurrent neural network grammars, in *Proc. of NAACL* (2016).",
      "J. Gehring, M. Auli, D. Grangier, D. Yarats, and Y. N. Dauphin, Convolutional sequence to sequence learning, arXiv:1705.03122v2 (2017).",
      "A. Graves, Generating sequences with recurrent neural networks, arXiv:1308.0850 (2013).",
      "K. He, X. Zhang, S. Ren, and J. Sun, Deep residual learning for image recognition, in *Proceedings of the IEEE Conference on Computer Vision and Pattern Recognition*, pp. 770–778 (2016).",
      "S. Hochreiter, Y. Bengio, P. Frasconi, and J. Schmidhuber, Gradient flow in recurrent nets: the difficulty of learning long-term dependencies (2001).",
      "S. Hochreiter and J. Schmidhuber, Long short-term memory, Neural Comput. **9**, 1735 (1997).",
      "Z. Huang and M. Harper, Self-training PCFG grammars with latent annotations across languages, in *Proceedings of the 2009 Conference on Empirical Methods in Natural Language Processing*, pp. 832–841 (ACL, 2009).",
      "R. Jozefowicz, O. Vinyals, M. Schuster, N. Shazeer, and Y. Wu, Exploring the limits of language modeling, arXiv:1602.02410 (2016).",
      "Ł. Kaiser and S. Bengio, Can active memory replace attention?, in *Advances in Neural Information Processing Systems (NIPS)* (2016).",
      "Ł. Kaiser and I. Sutskever, Neural GPUs learn algorithms, in *International Conference on Learning Representations (ICLR)* (2016).",
      "N. Kalchbrenner, L. Espeholt, K. Simonyan, A. van den Oord, A. Graves, and K. Kavukcuoglu, Neural machine translation in linear time, arXiv:1610.10099v2 (2017).",
      "Y. Kim, C. Denton, L. Hoang, and A. M. Rush, Structured attention networks, in *International Conference on Learning Representations* (2017).",
      "D. Kingma and J. Ba, Adam: A method for stochastic optimization, in *ICLR* (2015).",
      "O. Kuchaiev and B. Ginsburg, Factorization tricks for LSTM networks, arXiv:1703.10722 (2017).",
      "Z. Lin, M. Feng, C. N. dos Santos, M. Yu, B. Xiang, B. Zhou, and Y. Bengio, A structured self-attentive sentence embedding, arXiv:1703.03130 (2017).",
      "M.-T. Luong, Q. V. Le, I. Sutskever, O. Vinyals, and L. Kaiser, Multi-task sequence to sequence learning, arXiv:1511.06114 (2015).",
      "M.-T. Luong, H. Pham, and C. D. Manning, Effective approaches to attention-based neural machine translation, arXiv:1508.04025 (2015).",
      "M. P. Marcus, M. A. Marcinkiewicz, and B. Santorini, Building a large annotated corpus of English: The Penn Treebank, Comput. Linguist. **19**, 313 (1993).",
      "D. McClosky, E. Charniak, and M. Johnson, Effective self-training for parsing, in *Proceedings of the Human Language Technology Conference of the NAACL, Main Conference*, pp. 152–159 (ACL, 2006).",
      "A. Parikh, O. Täckström, D. Das, and J. Uszkoreit, A decomposable attention model, in *Empirical Methods in Natural Language Processing* (2016).",
      "R. Paulus, C. Xiong, and R. Socher, A deep reinforced model for abstractive summarization, arXiv:1705.04304 (2017).",
      "S. Petrov, L. Barrett, R. Thibaux, and D. Klein, Learning accurate, compact, and interpretable tree annotation, in *Proceedings of the 21st International Conference on Computational Linguistics and 44th Annual Meeting of the ACL*, pp. 433–440 (ACL, 2006).",
      "O. Press and L. Wolf, Using the output embedding to improve language models, arXiv:1608.05859 (2016).",
      "R. Sennrich, B. Haddow, and A. Birch, Neural machine translation of rare words with subword units, arXiv:1508.07909 (2015).",
      "N. Shazeer, A. Mirhoseini, K. Maziarz, A. Davis, Q. Le, G. Hinton, and J. Dean, Outrageously large neural networks: The sparsely-gated mixture-of-experts layer, arXiv:1701.06538 (2017).",
      "N. Srivastava, G. E. Hinton, A. Krizhevsky, I. Sutskever, and R. Salakhutdinov, Dropout: a simple way to prevent neural networks from overfitting, J. Mach. Learn. Res. **15**, 1929 (2014).",
      "S. Sukhbaatar, A. Szlam, J. Weston, and R. Fergus, End-to-end memory networks, in *Advances in Neural Information Processing Systems 28*, edited by C. Cortes, N. D. Lawrence, D. D. Lee, M. Sugiyama, and R. Garnett, pp. 2440–2448 (Curran Associates, 2015).",
      "I. Sutskever, O. Vinyals, and Q. V. Le, Sequence to sequence learning with neural networks, in *Advances in Neural Information Processing Systems*, pp. 3104–3112 (2014).",
      "C. Szegedy, V. Vanhoucke, S. Ioffe, J. Shlens, and Z. Wojna, Rethinking the inception architecture for computer vision, CoRR abs/1512.00567 (2015).",
      "Vinyals & Kaiser, Koo, Petrov, Sutskever, and Hinton, Grammar as a foreign language, in *Advances in Neural Information Processing Systems* (2015).",
      "Y. Wu, M. Schuster, Z. Chen, Q. V. Le, M. Norouzi, W. Macherey, M. Krikun, Y. Cao, Q. Gao, K. Macherey *et al.*, Google’s neural machine translation system: Bridging the gap between human and machine translation, arXiv:1609.08144 (2016).",
      "J. Zhou, Y. Cao, X. Wang, P. Li, and W. Xu, Deep recurrent models with fast-forward connections for neural machine translation, CoRR abs/1606.04199 (2016).",
      "M. Zhu, Y. Zhang, W. Chen, M. Zhang, and J. Zhu, Fast and accurate shift-reduce constituent parsing, in *Proceedings of the 51st Annual Meeting of the ACL (Volume 1: Long Papers)*, pp. 434–443 (ACL, 2013).",
    ],
    notes: [
      1: Note(
        label: "∗",
        text:
          "Equal contribution. Listing order is random. Jakob proposed replacing RNNs with self-attention and started the effort to evaluate this idea. Ashish, with Illia, designed and implemented the first Transformer models and has been crucially involved in every aspect of this work. Noam proposed scaled dot-product attention, multi-head attention and the parameter-free position representation and became the other person involved in nearly every detail. Niki designed, implemented, tuned and evaluated countless model variants in our original codebase and tensor2tensor. Llion also experimented with novel model variants, was responsible for our initial codebase, and efficient inference and visualizations. Lukasz and Aidan spent countless long days designing various parts of and implementing tensor2tensor, replacing our earlier codebase, greatly improving results and massively accelerating our research."
      ),
      2: Note(label: "†", text: "Work performed while at Google Brain."),
      3: Note(label: "‡", text: "Work performed while at Google Research."),
      4: Note(
        label: "4",
        text:
          #"To illustrate why the dot products get large, assume that the components of $q$ and $k$ are independent random variables with mean $0$ and variance $1$. Then their dot product, $q \cdot k = \sum_{i=1}^{d_k} q_i k_i$, has mean $0$ and variance $d_k$."#
      ),
      5: Note(label: "5", text: "We used values of 2.8, 3.7, 6.0 and 9.5 TFLOPS for K80, K40, M40 and P100, respectively."),
    ],
    authorNotes: [[1], [1], [1], [1], [1], [1, 2], [1], [1, 3]],
    acknowledgements: "We are grateful to Nal Kalchbrenner and Stephan Gouws for their fruitful comments, corrections and inspiration.",
    paged: true)
}
