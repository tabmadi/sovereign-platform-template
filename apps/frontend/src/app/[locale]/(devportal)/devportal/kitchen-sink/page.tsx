// The rendered design catalogue (ADR-0400, ADR-0701): the only place the design system can be seen whole.
import { ArrowRightIcon, PlusIcon } from "lucide-react";
import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Progress } from "@/components/ui/progress";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

export const metadata: Metadata = { title: "Design catalogue" };

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="border-t border-border py-6 first:border-t-0">
      <h2 className="text-lg font-semibold text-foreground">{title}</h2>
      <div className="mt-3 flex flex-wrap items-center gap-3">{children}</div>
    </section>
  );
}

// A colour role, shown as the pair it is: the surface and the text that goes on it.
// Classes are written out rather than composed, because Tailwind only sees literals.
function Swatch({ token, surface, label }: { token: string; surface: string; label: string }) {
  return (
    <figure className="w-40">
      <div
        className={`flex h-16 items-center justify-center rounded-lg border border-border ${surface}`}
      >
        <span className="text-sm font-medium">{label}</span>
      </div>
      <figcaption className="mt-1.5 font-mono text-xs text-muted-foreground">{token}</figcaption>
    </figure>
  );
}

const sampleRows = [
  { id: "1", name: "Starter seat", price: "$19.00", state: "Active" },
  { id: "2", name: "Team seat", price: "$49.00", state: "Active" },
  { id: "3", name: "Business seat", price: "$99.00", state: "Trialling" },
];

export default function KitchenSink() {
  return (
    <main className="mx-auto max-w-3xl p-6">
      <header>
        <h1 className="text-2xl font-semibold text-foreground">Design catalogue</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          The brand, then every primitive under <code>src/components/ui/</code>, rendered once. Why
          each role exists is <code>docs/brand.md</code>; the values themselves live only in{" "}
          <code>src/styles/theme.css</code>.
        </p>
      </header>

      <Section title="Brand — colour roles">
        <Swatch
          token="--background / --foreground"
          surface="bg-background text-foreground"
          label="Page"
        />
        <Swatch
          token="--card / --card-foreground"
          surface="bg-card text-card-foreground"
          label="Card"
        />
        <Swatch
          token="--primary / --primary-foreground"
          surface="bg-primary text-primary-foreground"
          label="Primary"
        />
        <Swatch
          token="--secondary / --secondary-foreground"
          surface="bg-secondary text-secondary-foreground"
          label="Secondary"
        />
        <Swatch
          token="--muted / --muted-foreground"
          surface="bg-muted text-muted-foreground"
          label="Muted"
        />
        <Swatch
          token="--accent / --accent-foreground"
          surface="bg-accent text-accent-foreground"
          label="Accent"
        />
        <Swatch
          token="--destructive / --destructive-foreground"
          surface="bg-destructive text-destructive-foreground"
          label="Destructive"
        />
        <Swatch
          token="--sidebar / --sidebar-foreground"
          surface="bg-sidebar text-sidebar-foreground"
          label="Sidebar"
        />
      </Section>

      <Section title="Brand — chart ramp">
        <div className="flex w-full overflow-hidden rounded-lg border border-border">
          <div className="h-12 flex-1 bg-chart-1" />
          <div className="h-12 flex-1 bg-chart-2" />
          <div className="h-12 flex-1 bg-chart-3" />
          <div className="h-12 flex-1 bg-chart-4" />
          <div className="h-12 flex-1 bg-chart-5" />
        </div>
        <p className="text-sm text-muted-foreground">
          Five steps, ordered. A sixth series is a sign the chart wants a different form, not a
          sixth colour.
        </p>
      </Section>

      <Section title="Brand — type scale">
        <div className="w-full space-y-2">
          <p className="text-4xl font-semibold tracking-tight">Display — 4xl semibold</p>
          <p className="text-2xl font-semibold">Page title — 2xl semibold</p>
          <p className="text-lg font-semibold">Section — lg semibold</p>
          <p className="text-base">Body — base regular, the default for prose.</p>
          <p className="text-sm text-muted-foreground">
            Secondary — sm on muted foreground, for anything explanatory.
          </p>
          <p className="font-mono text-sm">Mono — identifiers, amounts, spec fragments.</p>
        </div>
      </Section>

      <Section title="Brand — radius and elevation">
        <div className="rounded-sm border border-border p-4 text-sm">rounded-sm</div>
        <div className="rounded-md border border-border p-4 text-sm">rounded-md</div>
        <div className="rounded-lg border border-border p-4 text-sm">rounded-lg</div>
        <div className="rounded-xl border border-border p-4 text-sm">rounded-xl</div>
        <div className="rounded-lg bg-card p-4 text-sm shadow-xs">shadow-xs</div>
        <div className="rounded-lg bg-card p-4 text-sm shadow-md">shadow-md</div>
      </Section>

      <Section title="Button — variants">
        <Button>Default</Button>
        <Button variant="secondary">Secondary</Button>
        <Button variant="outline">Outline</Button>
        <Button variant="ghost">Ghost</Button>
        <Button variant="destructive">Delete</Button>
        <Button variant="link">Link</Button>
      </Section>

      <Section title="Button — sizes, icons and state">
        <Button size="xs">Extra small</Button>
        <Button size="sm">Small</Button>
        <Button size="lg">Large</Button>
        <Button>
          <PlusIcon />
          Add item
        </Button>
        <Button variant="secondary">
          Continue
          <ArrowRightIcon />
        </Button>
        <Button disabled>Disabled</Button>
      </Section>

      <Section title="Badge">
        <Badge>Default</Badge>
        <Badge variant="secondary">Secondary</Badge>
        <Badge variant="outline">Outline</Badge>
        <Badge variant="destructive">Failed</Badge>
        <Badge variant="ghost">Ghost</Badge>
      </Section>

      <Section title="Field — the form composition primitive">
        <FieldGroup className="max-w-xs">
          <Field>
            <FieldLabel htmlFor="ks-email">Email</FieldLabel>
            <Input id="ks-email" type="email" placeholder="you@example.com" />
            <FieldDescription>Where a receipt is sent.</FieldDescription>
          </Field>
          <Field data-invalid>
            <FieldLabel htmlFor="ks-invalid">Product id</FieldLabel>
            <Input id="ks-invalid" aria-invalid defaultValue="nope" />
            <FieldError>That doesn’t look like a product id.</FieldError>
          </Field>
          <Field>
            <FieldLabel htmlFor="ks-note">Note</FieldLabel>
            <Textarea id="ks-note" placeholder="Anything the next operator should know." />
          </Field>
        </FieldGroup>
      </Section>

      <Section title="Checkbox, radio and switch">
        <div className="flex items-center gap-2">
          <Checkbox id="ks-check" />
          <Label htmlFor="ks-check">Send me the digest</Label>
        </div>
        <RadioGroup defaultValue="monthly" className="flex gap-4">
          <div className="flex items-center gap-2">
            <RadioGroupItem value="monthly" id="ks-monthly" />
            <Label htmlFor="ks-monthly">Monthly</Label>
          </div>
          <div className="flex items-center gap-2">
            <RadioGroupItem value="annual" id="ks-annual" />
            <Label htmlFor="ks-annual">Annual</Label>
          </div>
        </RadioGroup>
        <div className="flex items-center gap-2">
          <Switch id="ks-switch" />
          <Label htmlFor="ks-switch">Enable previews</Label>
        </div>
      </Section>

      <Section title="Select">
        <div className="w-full max-w-xs space-y-1.5">
          <Label htmlFor="ks-env">Environment</Label>
          <Select>
            <SelectTrigger id="ks-env">
              <SelectValue placeholder="Choose an environment" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="dev">Development</SelectItem>
              <SelectItem value="staging">Staging</SelectItem>
              <SelectItem value="prod">Production</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </Section>

      <Section title="Card">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>Team seat</CardTitle>
            <CardDescription>Billed monthly, cancel whenever.</CardDescription>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            Includes every console surface, audit log retention, and two support seats.
          </CardContent>
          <CardFooter>
            <Button size="sm">Choose plan</Button>
          </CardFooter>
        </Card>
      </Section>

      <Section title="Tabs">
        <Tabs defaultValue="overview" className="w-full">
          <TabsList>
            <TabsTrigger value="overview">Overview</TabsTrigger>
            <TabsTrigger value="usage">Usage</TabsTrigger>
            <TabsTrigger value="limits">Limits</TabsTrigger>
          </TabsList>
          <TabsContent value="overview" className="pt-3 text-sm text-muted-foreground">
            What the account looks like right now.
          </TabsContent>
          <TabsContent value="usage" className="pt-3 text-sm text-muted-foreground">
            Consumption over the billing period.
          </TabsContent>
          <TabsContent value="limits" className="pt-3 text-sm text-muted-foreground">
            The ceilings that apply, and who can raise them.
          </TabsContent>
        </Tabs>
      </Section>

      <Section title="Table">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Product</TableHead>
              <TableHead className="text-end">Price</TableHead>
              <TableHead>State</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {sampleRows.map((row) => (
              <TableRow key={row.id}>
                <TableCell className="font-medium">{row.name}</TableCell>
                <TableCell className="text-end tabular-nums">{row.price}</TableCell>
                <TableCell>
                  <Badge variant={row.state === "Active" ? "secondary" : "outline"}>
                    {row.state}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Section>

      <Section title="Dialog">
        <Dialog>
          <DialogTrigger asChild>
            <Button variant="outline">Revoke key</Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Revoke this key?</DialogTitle>
              <DialogDescription>
                Anything using it stops working immediately. This cannot be undone.
              </DialogDescription>
            </DialogHeader>
          </DialogContent>
        </Dialog>
      </Section>

      <Section title="Dropdown menu">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline">Actions</Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start">
            <DropdownMenuLabel>This product</DropdownMenuLabel>
            <DropdownMenuItem>Edit</DropdownMenuItem>
            <DropdownMenuItem>Duplicate</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem variant="destructive">Delete</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </Section>

      <Section title="Tooltip">
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="outline">Hover me</Button>
            </TooltipTrigger>
            <TooltipContent>Explains the control, never replaces its label.</TooltipContent>
          </Tooltip>
        </TooltipProvider>
      </Section>

      <Section title="Avatar, progress, skeleton and separator">
        <Avatar>
          <AvatarFallback>TB</AvatarFallback>
        </Avatar>
        {/* A progressbar with no accessible name is a serious axe violation; the
            label is what the value is progress TOWARDS. */}
        <Progress value={62} className="w-40" aria-label="Storage used" />
        <Skeleton className="h-8 w-40" />
        <Separator orientation="vertical" className="h-8" />
        <Skeleton className="size-8 rounded-full" />
      </Section>
    </main>
  );
}
