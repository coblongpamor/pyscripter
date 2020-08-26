{-----------------------------------------------------------------------------
 Unit Name: dlgUnitTestWizard
 Author:    Kiriakos Vlahos
 Date:      09-Feb-2006
 Purpose:   Unit Test Wizard
 History:
-----------------------------------------------------------------------------}
unit dlgUnitTestWizard;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.UITypes,
  System.SysUtils,
  System.Variants,
  System.Classes,
  System.ImageList,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Buttons,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.ImgList,
  Vcl.VirtualImageList,
  TB2Item,
  SpTBXItem,
  VirtualTrees,
  frmCodeExplorer,
  cPythonSourceScanner,
  dlgPyIDEBase;

type

  TModuleUTWNode = class(TModuleCENode)
  public
    constructor CreateFromModule(AModule : TParsedModule);
  end;

  TClassUTWNode = class(TClassCENode)
    constructor CreateFromClass(AClass : TParsedClass);
  end;

  TFunctionUTWNode = class(TFunctionCENode)
    constructor CreateFromFunction(AFunction : TParsedFunction);
  end;

  TMethodUTWNode = class(TFunctionUTWNode)
  protected
    function GetHint: string; override;
    function GetImageIndex : integer; override;
  end;

  TUnitTestWizard = class(TPyIDEDlgBase)
    Panel1: TPanel;
    ExplorerTree: TVirtualStringTree;
    Bevel1: TBevel;
    PopupUnitTestWizard: TSpTBXPopupMenu;
    mnSelectAll: TSpTBXItem;
    mnDeselectAll: TSpTBXItem;
    Label1: TLabel;
    lbHeader: TLabel;
    lbFileName: TLabel;
    OKButton: TButton;
    BitBtn2: TButton;
    HelpButton: TButton;
    vilCodeImages: TVirtualImageList;
    vilImages: TVirtualImageList;
    procedure HelpButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ExplorerTreeInitNode(Sender: TBaseVirtualTree; ParentNode,
      Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
    procedure ExplorerTreeInitChildren(Sender: TBaseVirtualTree;
      Node: PVirtualNode; var ChildCount: Cardinal);
    procedure ExplorerTreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure ExplorerTreeGetImageIndex(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
      var Ghosted: Boolean; var ImageIndex: TImageIndex);
    procedure ExplorerTreeGetHint(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; var LineBreakStyle: TVTTooltipLineBreakStyle;
      var HintText: string);
    procedure mnSelectAllClick(Sender: TObject);
    procedure mnDeselectAllClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    ModuleUTWNode : TModuleUTWNode;
    class function GenerateTests(ModuleFileName, ModuleSource : string) : string;
  end;

implementation

uses
  JvJVCLUtils,
  SpTBXSkins,
  dmCommands,
  uCommonFunctions;

{$R *.dfm}

Type
  PNodeDataRec = ^TNodeDataRec;
  TNodeDataRec = record
    UTWNode : TAbstractCENode;
  end;


{ TModuleUTWNode }

constructor TModuleUTWNode.CreateFromModule(AModule: TParsedModule);
Var
  i : integer;
  CodeElement : TCodeElement;
  ClassNode : TClassCENode;
begin
  inherited Create;
  fCodeElement := AModule;
  fExpanded := esExpanded;
  for i := 0 to Module.ChildCount - 1 do begin
    CodeElement := Module.Children[i];
    if CodeElement is TParsedClass then begin
      ClassNode := TClassUTWNode.CreateFromClass(TParsedClass(CodeElement));
      AddChild(ClassNode);
    end else if CodeElement is TParsedFunction then
      AddChild(TFunctionUTWNode.CreateFromFunction(TParsedFunction(CodeElement)));
  end;
end;

{ TClassWTZNode }

constructor TClassUTWNode.CreateFromClass(AClass: TParsedClass);
Var
  i : integer;
  CE : TCodeElement;
begin
  inherited Create;
  fCodeElement := AClass;
  fExpanded := esExpanded;
  for i := 0 to ParsedClass.ChildCount - 1 do begin
    CE := ParsedClass.Children[i];
    if CE is TParsedFunction then
      AddChild(TMethodUTWNode.CreateFromFunction(TParsedFunction(CE)));
  end;
end;

{ TFunctionUTWNode }

constructor TFunctionUTWNode.CreateFromFunction(AFunction: TParsedFunction);
begin
  inherited Create;
  fCodeElement := AFunction;
end;

{ TMethodWTZNode }

function TMethodUTWNode.GetImageIndex: integer;
begin
  Result := Integer(TCodeImages.Method);
end;

function TMethodUTWNode.GetHint: string;
Var
  Doc : string;
begin
  Result := Format('Method %s defined at line %d'#13#10'Arguments: %s',
              [fCodeElement.Name, fCodeElement.CodePos.LineNo, ParsedFunction.ArgumentsString]);
  Doc := ParsedFunction.DocString;
  if Doc <> '' then
    Result := Result + #13#10#13#10 + Doc;
end;

class function TUnitTestWizard.GenerateTests(ModuleFileName,
  ModuleSource: string) : string;

Const
  Header = '#This file was originally generated by PyScripter''s unit test wizard' +
    SLineBreak + SLineBreak + 'import unittest'+ sLineBreak + 'import %s'
    + sLineBreak + sLineBreak;

   ClassHeader =
      'class Test%s(unittest.TestCase):'+ sLineBreak + SLineBreak +
      '    def setUp(self): ' + SLineBreak +
      '        pass' + SLineBreak + SLineBreak +
      '    def tearDown(self): ' + SLineBreak +
      '        pass' + SLineBreak + SLineBreak;

    MethodHeader =
        '    def test%s(self):' + SLineBreak +
        '        pass' + SLineBreak + SLineBreak;

     Footer =
      'if __name__ == ''__main__'':' + SLineBreak +
      '    unittest.main()' + SLineBreak;

Var
  Node, MethodNode: PVirtualNode;
  Data, MethodData : PNodeDataRec;
  ParsedModule : TParsedModule;
  PythonScanner : TPythonScanner;
  FunctionTests : string;
  WaitCursorInterface: IInterface;
begin
  Application.ProcessMessages;
  Result := '';
  FunctionTests := '';
  PythonScanner := TPythonScanner.Create;
  ParsedModule := TParsedModule.Create(ModuleFileName, ModuleSource);
  try
    if PythonScanner.ScanModule(ParsedModule) then begin
      with TUnitTestWizard.Create(Application) do begin
        ModuleUTWNode := TModuleUTWNode.CreateFromModule(ParsedModule);
        lbFileName.Caption := ModuleFileName;
        // Turn off Animation to speed things up
        ExplorerTree.TreeOptions.AnimationOptions :=
          ExplorerTree.TreeOptions.AnimationOptions - [toAnimatedToggle];
        ExplorerTree.RootNodeCount := 1;
        ExplorerTree.ReinitNode(ExplorerTree.RootNode, True);
        ExplorerTree.TreeOptions.AnimationOptions :=
          ExplorerTree.TreeOptions.AnimationOptions + [toAnimatedToggle];
        if ShowModal = idOK then begin
          Application.ProcessMessages;
          WaitCursorInterface := WaitCursor;
          // Generate code
          Result := Format(Header, [FileNameToModuleName(ModuleFileName)]);
          Node := (ExplorerTree.RootNode)^.FirstChild^.FirstChild;
          while Assigned(Node) do begin
            Data := PNodeDataRec(ExplorerTree.GetNodeData(Node));
            if (Node.CheckState in [csCheckedNormal, csCheckedPressed,
              csMixedNormal, csMixedPressed]) then
            begin
              if Data.UTWNode is TClassUTWNode then begin
                Result := Result + Format(ClassHeader, [Data.UTWNode.CodeElement.Name]);
                MethodNode := Node.FirstChild;
                while Assigned(MethodNode) do begin
                  if (MethodNode.CheckState in [csCheckedNormal, csCheckedPressed]) then begin
                    MethodData := PNodeDataRec(ExplorerTree.GetNodeData(MethodNode));
                    Result := Result + Format(MethodHeader, [MethodData.UTWNode.CodeElement.Name]);
                  end;
                  MethodNode := MethodNode.NextSibling;
                end;
              end else if Data.UTWNode is TFunctionUTWNode then begin
                if FunctionTests = '' then
                  FunctionTests := Format(ClassHeader, ['GlobalFunctions']);
                FunctionTests := FunctionTests + Format(MethodHeader, [Data.UTWNode.CodeElement.Name]);
              end;
            end;
            Node := Node.NextSibling;
          end;
          if FunctionTests <> '' then
            Result := Result + FunctionTests;
          Result := Result + Footer;
        end;
        ModuleUTWNode.Free;
        Release;
      end;
    end;
  finally
    ParsedModule.Free;
    PythonScanner.Free;
  end;
end;

procedure TUnitTestWizard.ExplorerTreeGetHint(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex;
  var LineBreakStyle: TVTTooltipLineBreakStyle; var HintText: string);
var
  Data : PNodeDataRec;
begin
  Data := ExplorerTree.GetNodeData(Node);
  HintText := Data.UTWNode.Hint;
end;

procedure TUnitTestWizard.ExplorerTreeGetImageIndex(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: TImageIndex);
var
  Data : PNodeDataRec;
begin
  if Kind in [ikNormal, ikSelected] then begin
    Data := ExplorerTree.GetNodeData(Node);
    ImageIndex := Data.UTWNode.ImageIndex;
  end;
end;

procedure TUnitTestWizard.ExplorerTreeGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
var
  Data : PNodeDataRec;
begin
  Data := ExplorerTree.GetNodeData(Node);
  if Assigned(Data) then
    CellText := Data.UTWNode.Caption;
end;

procedure TUnitTestWizard.ExplorerTreeInitChildren(Sender: TBaseVirtualTree;
  Node: PVirtualNode; var ChildCount: Cardinal);
var
  Data : PNodeDataRec;
begin
  Data := ExplorerTree.GetNodeData(Node);
  ChildCount := Data.UTWNode.ChildCount;
end;

procedure TUnitTestWizard.ExplorerTreeInitNode(Sender: TBaseVirtualTree;
  ParentNode, Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
var
  Data, ParentData: PNodeDataRec;
begin
  Data := ExplorerTree.GetNodeData(Node);
  if ExplorerTree.GetNodeLevel(Node) = 0 then begin
    Data.UTWNode := ModuleUTWNode;
  end else begin
    ParentData := ExplorerTree.GetNodeData(ParentNode);
    Data.UTWNode :=
      ParentData.UTWNode.Children[Node.Index] as TAbstractCENode;
  end;
  if Data.UTWNode.CodeElement.Name = '__init__' then
    Node.CheckState := csUncheckedNormal
  else
    Node.CheckState := csCheckedNormal;
  if Data.UTWNode.ChildCount > 0 then begin
    Node.CheckType := ctTriStateCheckBox;
    if Data.UTWNode.Expanded = esExpanded then
      InitialStates := [ivsHasChildren, ivsExpanded]
    else
      InitialStates := [ivsHasChildren];
  end else
    Node.CheckType := ctCheckBox;
end;

procedure TUnitTestWizard.FormCreate(Sender: TObject);
begin
  inherited;
  ExplorerTree.NodeDataSize := SizeOf(TNodeDataRec);
end;

procedure TUnitTestWizard.HelpButtonClick(Sender: TObject);
begin
  if HelpContext <> 0 then
    Application.HelpContext(HelpContext);
end;

procedure TUnitTestWizard.mnDeselectAllClick(Sender: TObject);
Var
  Node : PVirtualNode;
begin
   Node := ExplorerTree.RootNode^.FirstChild;
   while Assigned(Node) do begin
     ExplorerTree.CheckState[Node] := csUncheckedNormal;
     Node := Node.NextSibling;
   end;
end;

procedure TUnitTestWizard.mnSelectAllClick(Sender: TObject);
Var
  Node : PVirtualNode;
begin
   Node := ExplorerTree.RootNode^.FirstChild;
   while Assigned(Node) do begin
     ExplorerTree.CheckState[Node] := csCheckedNormal;
     Node := Node.NextSibling;
   end;
end;

end.
